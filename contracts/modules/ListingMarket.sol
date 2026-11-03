// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TrustSchedule} from "./TrustSchedule.sol";
import {PeriodPricing} from "../libraries/PeriodPricing.sol";

/// @title ListingMarket：受益權承購市場
/// @notice 任何持有人（受益人或承購人）都能掛單出售未到期的期數；
///         售價不得低於用年化上限折現的價格，保護賣方不被壓價。
abstract contract ListingMarket is TrustSchedule {
    using SafeERC20 for IERC20;

    function _initMarket(Config calldata c) internal {
        if (c.periodsPerYear == 0 || c.maxAprBps == 0 || c.maxAprBps > BPS * 10) revert InvalidParams();
        maxAprBps = c.maxAprBps;
        periodsPerYear = c.periodsPerYear;
    }

    function listPeriods(uint256 fromId, uint256 toId, uint256 priceTokens) external returns (uint256 listingId) {
        _checkSellable(msg.sender, fromId, toId);
        uint256 price = priceTokens * unit;
        if (price == 0) revert ZeroAmount();
        if (price >= (toId - fromId + 1) * amountPerPeriod) revert PriceTooHigh();
        if (price < quote(fromId, toId, maxAprBps)) revert AprTooHigh();
        listingId = _listings.length;
        _listings.push(Listing(fromId, toId, price, true, msg.sender, address(0)));
        for (uint256 i = fromId; i <= toId; i++) _listedIn[i] = listingId + 1;
        emit Listed(listingId, msg.sender, fromId, toId, price);
    }

    function cancelListing(uint256 listingId) external {
        Listing storage l = _activeListing(listingId);
        if (msg.sender != l.seller) revert PeriodNotOwned();
        l.active = false;
        _unlist(l.fromId, l.toId);
        emit ListingCancelled(listingId);
    }

    function buy(uint256 listingId) external nonReentrant {
        Listing storage l = _activeListing(listingId);
        if (msg.sender == l.seller || msg.sender == beneficiary) revert CannotBuyOwn();
        if (msg.sender == settlor) revert SettlorCannotBuy();
        if (l.seller == beneficiary && _isPaused()) revert TrustPaused();
        if (l.fromId < _dueCount()) revert PeriodAlreadyDue();
        if (l.price < quote(l.fromId, l.toId, maxAprBps)) revert AprTooHigh();
        if (!_isFullyFunded()) revert NotFullyFunded();
        l.active = false;
        l.buyer = msg.sender;
        _unlist(l.fromId, l.toId);
        _setHolder(l.fromId, l.toId, msg.sender);
        token.safeTransferFrom(msg.sender, l.seller, l.price);
        emit PeriodsSold(listingId, msg.sender, l.price);
    }

    /// @notice 承購人把期數轉給別人（受益人不能直接轉，避免繞過定價保護）
    function transferPeriods(address to, uint256 fromId, uint256 toId) external {
        if (msg.sender == beneficiary) revert BeneficiaryCannotTransfer();
        if (to == address(0) || to == settlor || to == msg.sender) revert InvalidParams();
        if (fromId > toId || toId >= totalPeriods) revert InvalidRange();
        for (uint256 i = fromId; i <= toId; i++) {
            if (claimed[i] || periodOwner(i) != msg.sender) revert PeriodNotOwned();
            if (_listedIn[i] != 0) revert AlreadyListed();
        }
        _setHolder(fromId, toId, to);
        emit PeriodsTransferred(msg.sender, to, fromId, toId);
    }

    // ── 報價與揭露 ──
    function quote(uint256 fromId, uint256 toId, uint256 aprBps) public view returns (uint256) {
        if (fromId > toId || toId >= totalPeriods) revert InvalidRange();
        uint256 due = _dueCount();
        if (fromId < due) revert PeriodAlreadyDue();
        return PeriodPricing.presentValue(amountPerPeriod, fromId + 1 - due, toId - fromId + 1, aprBps, periodsPerYear);
    }

    function impliedAprBps(uint256 listingId) external view returns (uint256) {
        Listing storage l = _listings[listingId];
        uint256 due = _dueCount();
        if (!l.active || l.fromId < due) return 0;
        return PeriodPricing.impliedApr(l.price, amountPerPeriod, l.fromId + 1 - due, l.toId - l.fromId + 1, periodsPerYear);
    }

    function listingDiscountBps(uint256 listingId) external view returns (uint256) {
        Listing storage l = _listings[listingId];
        uint256 face = (l.toId - l.fromId + 1) * amountPerPeriod;
        return (face - l.price) * BPS / face;
    }

    function listingsCount() external view returns (uint256) {
        return _listings.length;
    }

    function getListings() external view returns (Listing[] memory) {
        return _listings;
    }

    // ── 內部（BidBook 也會用）──
    function _checkSellable(address seller, uint256 fromId, uint256 toId) internal view {
        if (seller == settlor) revert SettlorCannotBuy();
        if (seller == beneficiary && _isPaused()) revert TrustPaused();
        if (fromId > toId || toId >= totalPeriods) revert InvalidRange();
        if (fromId < _dueCount()) revert PeriodAlreadyDue();
        for (uint256 i = fromId; i <= toId; i++) {
            if (periodOwner(i) != seller) revert PeriodNotOwned();
            if (_listedIn[i] != 0) revert AlreadyListed();
        }
        if (!_isFullyFunded()) revert NotFullyFunded();
    }

    function _activeListing(uint256 listingId) internal view returns (Listing storage l) {
        if (listingId >= _listings.length) revert ListingNotActive();
        l = _listings[listingId];
        if (!l.active) revert ListingNotActive();
    }

    function _unlist(uint256 fromId, uint256 toId) internal {
        for (uint256 i = fromId; i <= toId; i++) _listedIn[i] = 0;
    }
}
