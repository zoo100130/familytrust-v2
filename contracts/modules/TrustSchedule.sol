// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TrustStorage} from "../storage/TrustStorage.sol";

/// @title TrustSchedule：撥款排程（核心）
/// @notice 錢怎麼進來、每一期屬於誰、到期後怎麼領。沒有把錢退給出資人的函式。
abstract contract TrustSchedule is TrustStorage {
    using SafeERC20 for IERC20;

    modifier onlySettlor() {
        if (msg.sender != settlor) revert NotSettlor();
        _;
    }

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert NotBeneficiary();
        _;
    }

    modifier nonReentrant() {
        if (_lock == 1) revert Reentrancy();
        _lock = 1;
        _;
        _lock = 0;
    }

    function _initSchedule(Config calldata c) internal {
        if (
            c.token == address(0) || c.settlor == address(0) || c.beneficiary == address(0)
                || c.beneficiary == c.settlor || c.intervalSeconds == 0 || c.amountPerPeriodTokens == 0
                || c.totalPeriods == 0 || c.periodsAlreadyDue >= c.totalPeriods
        ) revert InvalidParams();
        uint256 u = 10 ** IERC20Metadata(c.token).decimals();
        token = IERC20(c.token);
        settlor = c.settlor;
        beneficiary = c.beneficiary;
        unit = u;
        interval = c.intervalSeconds;
        amountPerPeriod = c.amountPerPeriodTokens * u;
        totalPeriods = c.totalPeriods;
        startTime = block.timestamp - c.periodsAlreadyDue * c.intervalSeconds;
    }

    /// @dev 由 SettlorControls 實作（Template Method）
    function _isPaused() internal view virtual returns (bool);

    // ── 存入與領取 ──
    function fund(uint256 amountTokens) external onlySettlor nonReentrant {
        uint256 amount = amountTokens * unit;
        if (amount == 0) revert ZeroAmount();
        if (poolBalance() + amount > unpaidLiabilities()) revert OverFunded();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice 領取自己持有、已到期的期數（受益人與承購人共用）
    function claim() external nonReentrant {
        uint256 amount = _claimDue(msg.sender);
        token.safeTransfer(msg.sender, amount);
    }

    /// @dev 標記已領並回傳金額；轉帳由呼叫者決定給誰
    function _claimDue(address who) internal returns (uint256 amount) {
        bool blocked = who == beneficiary && _isPaused();
        uint256 due = _dueCount();
        uint256 count;
        for (uint256 i = 0; i < due; i++) {
            if (blocked || claimed[i] || periodOwner(i) != who) continue;
            claimed[i] = true;
            count++;
        }
        if (count == 0) {
            if (blocked) revert TrustPaused();
            revert NothingToClaim();
        }
        amount = count * amountPerPeriod;
        if (poolBalance() < amount + _reservedForOthers(who)) revert InsufficientFunds();
        claimedCount += count;
        emit Claimed(who, count, amount);
    }

    // ── 內部 ──
    function _dueCount() internal view returns (uint256 n) {
        if (block.timestamp < startTime) return 0;
        n = (block.timestamp - startTime) / interval;
        if (n > totalPeriods) n = totalPeriods;
    }

    function _reservedForOthers(address exclude) internal view returns (uint256 total) {
        for (uint256 i = 0; i < totalPeriods; i++) {
            if (claimed[i]) continue;
            address h = _holder[i];
            if (h != address(0) && h != exclude) total += amountPerPeriod;
        }
    }

    function _isFullyFunded() internal view returns (bool) {
        return poolBalance() >= unpaidLiabilities();
    }

    function _setHolder(uint256 fromId, uint256 toId, address to) internal {
        address h = to == beneficiary ? address(0) : to;
        for (uint256 i = fromId; i <= toId; i++) _holder[i] = h;
    }

    // ── 查詢 ──
    /// @notice 信託資金池（不含做市商託管的錢）
    function poolBalance() public view returns (uint256) {
        return token.balanceOf(address(this)) - bidEscrow;
    }

    function periodOwner(uint256 i) public view returns (address) {
        address h = _holder[i];
        return h == address(0) ? beneficiary : h;
    }

    function dueTime(uint256 i) public view returns (uint256) {
        return startTime + (i + 1) * interval;
    }

    function unpaidLiabilities() public view returns (uint256) {
        return (totalPeriods - claimedCount) * amountPerPeriod;
    }

    function coverageBps() external view returns (uint256) {
        uint256 owed = unpaidLiabilities();
        if (owed == 0) return BPS;
        return poolBalance() * BPS / owed;
    }

    function claimable(address who) external view returns (uint256 periods, uint256 amount) {
        if (who == beneficiary && _isPaused()) return (0, 0);
        uint256 due = _dueCount();
        for (uint256 i = 0; i < due; i++) {
            if (!claimed[i] && periodOwner(i) == who) periods++;
        }
        amount = periods * amountPerPeriod;
    }

    function nextPayout() external view returns (bool exists, uint256 periodId, uint256 time) {
        uint256 due = _dueCount();
        if (due >= totalPeriods) return (false, 0, 0);
        return (true, due, dueTime(due));
    }

    /// @notice 一次讀出所有期數（給前端與做市商）
    function getPeriods() external view returns (address[] memory owners, bool[] memory claimedArr, uint256[] memory dueTimes) {
        uint256 n = totalPeriods;
        owners = new address[](n);
        claimedArr = new bool[](n);
        dueTimes = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            owners[i] = periodOwner(i);
            claimedArr[i] = claimed[i];
            dueTimes[i] = dueTime(i);
        }
    }
}
