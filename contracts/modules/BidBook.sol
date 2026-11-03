// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ListingMarket} from "./ListingMarket.sol";

/// @title BidBook：做市商常駐收購報價
/// @notice 做市商託管資金、開出「以 X% 年化收購、最多 N 期」；
///         持有人可以立即把期數賣給報價。託管的錢不算進信託資金池。
abstract contract BidBook is ListingMarket {
    using SafeERC20 for IERC20;

    function placeBid(uint256 aprBps, uint256 budgetTokens, uint256 maxPeriods_) external nonReentrant returns (uint256 bidId) {
        if (msg.sender == beneficiary) revert CannotBuyOwn();
        if (msg.sender == settlor) revert SettlorCannotBuy();
        if (aprBps > maxAprBps) revert AprTooHigh();
        uint256 budget = budgetTokens * unit;
        if (budget == 0 || maxPeriods_ == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), budget);
        bidEscrow += budget;
        bidId = _bids.length;
        _bids.push(Bid(msg.sender, aprBps, budget, maxPeriods_, true));
        emit BidPlaced(bidId, msg.sender, aprBps, budget, maxPeriods_);
    }

    /// @notice 取消報價，剩餘託管資金全額退回
    function cancelBid(uint256 bidId) external nonReentrant {
        Bid storage b = _activeBid(bidId);
        if (msg.sender != b.maker) revert NotBidMaker();
        _closeBid(b, bidId);
    }

    /// @notice 持有人把期數直接賣給報價，立即拿到錢
    function sellToBid(uint256 bidId, uint256 fromId, uint256 toId) external nonReentrant {
        Bid storage b = _activeBid(bidId);
        if (msg.sender == b.maker) revert CannotBuyOwn();
        _checkSellable(msg.sender, fromId, toId);
        uint256 n = toId - fromId + 1;
        if (n > b.maxPeriods) revert BidTooSmall();
        uint256 price = quote(fromId, toId, b.aprBps);
        if (price > b.budget) revert BidTooSmall();
        b.budget -= price;
        b.maxPeriods -= n;
        bidEscrow -= price;
        _setHolder(fromId, toId, b.maker);
        if (b.maxPeriods == 0 || b.budget == 0) _closeBid(b, bidId);
        token.safeTransfer(msg.sender, price);
        emit BidFilled(bidId, msg.sender, fromId, toId, price);
    }

    function bidsCount() external view returns (uint256) {
        return _bids.length;
    }

    function getBids() external view returns (Bid[] memory) {
        return _bids;
    }

    function _activeBid(uint256 bidId) internal view returns (Bid storage b) {
        if (bidId >= _bids.length || !_bids[bidId].active) revert BidNotActive();
        b = _bids[bidId];
    }

    function _closeBid(Bid storage b, uint256 bidId) internal {
        uint256 refund = b.budget;
        b.active = false;
        b.budget = 0;
        bidEscrow -= refund;
        if (refund > 0) token.safeTransfer(b.maker, refund);
        emit BidCancelled(bidId, refund);
    }
}
