// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TrustSchedule} from "./TrustSchedule.sol";

/// @title Payments：信託直付與收款方
/// @notice 出資人提名收款方（醫院、安養院…），受益人同意才生效；
///         受益人可以把到期款直接付給收款方，錢不經過受益人錢包。每段期間有上限。
abstract contract Payments is TrustSchedule {
    using SafeERC20 for IERC20;

    function _initPayments(Config calldata c) internal {
        if (c.payWindowSeconds == 0) revert InvalidParams();
        payWindow = c.payWindowSeconds;
    }

    // ── 收款方 ──
    function proposePayee(address payee, uint256 capTokens, string calldata label) external onlySettlor {
        if (payee == address(0) || payee == beneficiary || payee == settlor) revert InvalidParams();
        Payee storage p = _payees[payee];
        if (!p.proposed) _payeeList.push(payee);
        p.proposed = true;
        p.approved = false; // 條件改變就要重新同意
        p.cap = capTokens * unit;
        p.label = label;
        emit PayeeProposed(payee, p.cap, label);
    }

    function approvePayee(address payee) external onlyBeneficiary {
        Payee storage p = _payees[payee];
        if (!p.proposed) revert PayeeNotApproved();
        p.approved = true;
        emit PayeeApproved(payee);
    }

    /// @notice 出資人或受益人任一方都可以移除
    function removePayee(address payee) external {
        if (msg.sender != settlor && msg.sender != beneficiary) revert NotBeneficiary();
        Payee storage p = _payees[payee];
        p.proposed = false;
        p.approved = false;
        emit PayeeRemoved(payee, msg.sender);
    }

    // ── 付款 ──
    /// @notice 領取到期款，其中 amount 直接付給收款方，其餘轉給受益人
    function claimAndPay(address payee, uint256 amount, string calldata memo) external onlyBeneficiary nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 total = _claimDue(msg.sender);
        if (amount > total) revert InsufficientFunds();
        _usePayee(payee, amount);
        token.safeTransfer(payee, amount);
        if (total > amount) token.safeTransfer(msg.sender, total - amount);
        emit Paid(payee, amount, true, memo);
    }

    /// @notice 從受益人錢包付款（需先 approve），留下鏈上付款紀錄
    function payFromWallet(address payee, uint256 amount, string calldata memo) external onlyBeneficiary nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _usePayee(payee, amount);
        token.safeTransferFrom(msg.sender, payee, amount);
        emit Paid(payee, amount, false, memo);
    }

    function _usePayee(address payee, uint256 amount) internal {
        Payee storage p = _payees[payee];
        if (!p.proposed || !p.approved) revert PayeeNotApproved();
        uint256 w = block.timestamp / payWindow;
        uint256 used = paidInWindow[payee][w] + amount;
        if (p.cap != 0 && used > p.cap) revert PayCapExceeded();
        paidInWindow[payee][w] = used;
    }

    // ── 查詢 ──
    /// @notice 已移除的收款方 caps 回傳 type(uint256).max
    function getPayees()
        external
        view
        returns (address[] memory addrs, bool[] memory approved, uint256[] memory caps, uint256[] memory usedNow, string[] memory labels)
    {
        uint256 n = _payeeList.length;
        addrs = new address[](n);
        approved = new bool[](n);
        caps = new uint256[](n);
        usedNow = new uint256[](n);
        labels = new string[](n);
        for (uint256 i = 0; i < n; i++) {
            address a = _payeeList[i];
            Payee storage p = _payees[a];
            addrs[i] = a;
            approved[i] = p.proposed && p.approved;
            caps[i] = p.proposed ? p.cap : type(uint256).max;
            usedNow[i] = paidInWindow[a][block.timestamp / payWindow];
            labels[i] = p.label;
        }
    }
}
