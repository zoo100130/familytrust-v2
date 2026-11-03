// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PeriodPricing：時間價值純數學（單利）
/// @notice PV = Σ A ÷ (1 + r × (w + j) ÷ m)
///         A = 每期金額、r = 年化、w = 第一期還要等幾期、m = 一年幾期、j = 0…n-1
library PeriodPricing {
    uint256 internal constant BPS = 10_000;

    function presentValue(uint256 amountPerPeriod, uint256 firstWait, uint256 count, uint256 aprBps, uint256 periodsPerYear)
        internal
        pure
        returns (uint256 pv)
    {
        uint256 scale = BPS * periodsPerYear;
        for (uint256 j = 0; j < count; j++) {
            pv += amountPerPeriod * scale / (scale + aprBps * (firstWait + j));
        }
    }

    /// @notice 給售價反解年化：二分法 40 次，範圍 0～10000%
    function impliedApr(uint256 price, uint256 amountPerPeriod, uint256 firstWait, uint256 count, uint256 periodsPerYear)
        internal
        pure
        returns (uint256)
    {
        uint256 lo = 0;
        uint256 hi = BPS * 100;
        for (uint256 k = 0; k < 40; k++) {
            uint256 mid = (lo + hi) / 2;
            if (presentValue(amountPerPeriod, firstWait, count, mid, periodsPerYear) > price) lo = mid;
            else hi = mid;
        }
        return hi;
    }
}
