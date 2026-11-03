// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SettlorControls} from "./modules/SettlorControls.sol";
import {BidBook} from "./modules/BidBook.sol";
import {Payments} from "./modules/Payments.sol";

/// @title  FamilyTrustV2：可升級的鏈上信託
/// @notice 這個檔案只負責組裝模組與升級權限，部署時只部署這一份（Deploy with Proxy）。
///         - TrustSchedule   ：撥款排程（核心）
///         - SettlorControls ：出資人有上限的暫停
///         - ListingMarket   ：承購市場與期數轉讓
///         - BidBook         ：做市商收購報價
///         - Payments        ：信託直付與收款方
///         - TrustStorage    ：全部狀態變數（升級時只能往後加）
///         initialize 的 c 一次貼上，例如：
///          ["代幣Proxy","出資人","受益人",300,500,24,2500,12,3,6,3,1800]
contract FamilyTrustV2 is Initializable, UUPSUpgradeable, SettlorControls, BidBook, Payments {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Config calldata c) external initializer {
        _initSchedule(c);
        _initControls(c);
        _initMarket(c);
        _initPayments(c);
        upgradeAdmin = c.settlor;
        emit UpgradeAdminChanged(c.settlor);
    }

    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    // ── 升級 ──
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != upgradeAdmin) revert NotUpgradeAdmin();
        if (upgradesFrozen) revert UpgradesFrozen();
    }

    /// @notice 把升級權交給別人（例如之後的多簽）
    function setUpgradeAdmin(address admin) external {
        if (msg.sender != upgradeAdmin) revert NotUpgradeAdmin();
        if (admin == address(0)) revert InvalidParams();
        upgradeAdmin = admin;
        emit UpgradeAdminChanged(admin);
    }

    /// @notice 永久放棄升級權，規則從此固定
    function freezeUpgrades() external {
        if (msg.sender != upgradeAdmin) revert NotUpgradeAdmin();
        upgradesFrozen = true;
        emit UpgradesFrozenForever();
    }
}
