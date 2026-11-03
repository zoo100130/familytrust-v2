// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFamilyTrustV2} from "../interfaces/IFamilyTrustV2.sol";

/// @title TrustStorage：所有狀態變數集中在這裡
/// @notice 可升級合約的規則：
///         1. 只有這個檔案可以宣告狀態變數，其他模組不能有自己的變數
///         2. 升級時只能在最後面（__gap 之前）新增，並把 __gap 減少相同數量
///         3. 不能刪除、調換順序或改型別
abstract contract TrustStorage is IFamilyTrustV2 {
    uint256 internal constant BPS = 10_000;

    // ── 角色與設定（initialize 時寫入一次）──
    IERC20 public token;
    address public settlor;
    address public beneficiary;
    address public upgradeAdmin;
    bool public upgradesFrozen;

    uint256 public unit;
    uint256 public startTime;
    uint256 public interval;
    uint256 public amountPerPeriod;
    uint256 public totalPeriods;
    uint256 public maxAprBps;
    uint256 public periodsPerYear;
    uint256 public maxPausePeriods;
    uint256 public pauseBudgetPeriods;
    uint256 public payWindow;

    // ── 撥款排程 ──
    mapping(uint256 => bool) public claimed;
    mapping(uint256 => address) internal _holder; // 0 = 仍屬受益人
    uint256 public claimedCount;

    // ── 暫停 ──
    uint256 public pausedUntil;
    uint256 public pauseUsedPeriods;

    // ── 承購市場 ──
    Listing[] internal _listings;
    mapping(uint256 => uint256) internal _listedIn; // 掛單編號 + 1；0 = 沒掛

    // ── 做市報價 ──
    Bid[] internal _bids;
    uint256 public bidEscrow; // 做市商託管的錢，不屬於信託資金池

    // ── 支付 ──
    mapping(address => Payee) internal _payees;
    address[] internal _payeeList;
    mapping(address => mapping(uint256 => uint256)) public paidInWindow; // 收款方 => 期間編號 => 已付

    // ── 防重入 ──
    uint256 internal _lock;

    /// @dev 預留給未來升級的空位
    uint256[40] private __gap;
}
