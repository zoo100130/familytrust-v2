// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title RecordConsent：受益人授權他人查詢自己的財務紀錄
/// @notice 獨立合約，不需要重新部署 FamilyTrust。
///         只記錄「誰同意誰看哪些類別、到什麼時候」，本身不存任何紀錄內容。
///         注意：鏈上交易本來就公開，這份同意是「前端是否顯示」的閘門與可稽核的授權紀錄，不是加密。
contract RecordConsent {
    // 紀錄類別（位元旗標，可組合）
    uint8 public constant PAYMENTS = 1; // 支付：代幣轉帳
    uint8 public constant STAKING  = 2; // 質押
    uint8 public constant LENDING  = 4; // 借貸

    struct Grant {
        uint8 scopes;   // 同意的類別
        uint64 expiry;  // 到期時間（unix 秒）
    }

    /// owner（受益人）=> viewer（例如出資人）=> 授權
    mapping(address => mapping(address => Grant)) public grants;

    event Granted(address indexed owner, address indexed viewer, uint8 scopes, uint64 expiry);
    event Revoked(address indexed owner, address indexed viewer);

    error InvalidScopes();
    error InvalidExpiry();
    error SelfGrant();

    /// @notice 受益人開啟同意：只有本人能為自己的紀錄授權
    function grant(address viewer, uint8 scopes, uint64 expiry) external {
        if (viewer == msg.sender) revert SelfGrant();
        if (scopes == 0 || scopes > (PAYMENTS | STAKING | LENDING)) revert InvalidScopes();
        if (expiry <= block.timestamp) revert InvalidExpiry();
        grants[msg.sender][viewer] = Grant(scopes, expiry);
        emit Granted(msg.sender, viewer, scopes, expiry);
    }

    /// @notice 受益人隨時撤回
    function revoke(address viewer) external {
        delete grants[msg.sender][viewer];
        emit Revoked(msg.sender, viewer);
    }

    /// @notice 前端查詢：viewer 現在能不能看 owner 的某一類紀錄
    function canView(address owner, address viewer, uint8 scope) external view returns (bool) {
        Grant memory g = grants[owner][viewer];
        return g.expiry > block.timestamp && (g.scopes & scope) == scope;
    }
}
