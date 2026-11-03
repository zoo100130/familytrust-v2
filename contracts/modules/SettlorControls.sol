// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TrustSchedule} from "./TrustSchedule.sol";

/// @title SettlorControls：出資人有上限的暫停
/// @notice 只凍結受益人自己的期數；時間到自動恢復；暫停只延後、不沒收。
abstract contract SettlorControls is TrustSchedule {
    function _initControls(Config calldata c) internal {
        if (c.maxPausePeriods > c.pauseBudgetPeriods) revert InvalidParams();
        maxPausePeriods = c.maxPausePeriods;
        pauseBudgetPeriods = c.pauseBudgetPeriods;
    }

    function pause(uint256 periods) external onlySettlor {
        if (_isPaused()) revert AlreadyPaused();
        if (periods == 0 || periods > maxPausePeriods) revert PauseTooLong();
        if (pauseUsedPeriods + periods > pauseBudgetPeriods) revert PauseBudgetExceeded();
        pauseUsedPeriods += periods;
        pausedUntil = block.timestamp + periods * interval;
        emit Paused(msg.sender, pausedUntil);
    }

    /// @notice 提早恢復，用掉的額度不退
    function unpause() external onlySettlor {
        if (!_isPaused()) revert NotPaused();
        pausedUntil = block.timestamp;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return _isPaused();
    }

    function pauseBudgetLeft() external view returns (uint256) {
        return pauseBudgetPeriods - pauseUsedPeriods;
    }

    function _isPaused() internal view override returns (bool) {
        return block.timestamp < pausedUntil;
    }
}
