// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IMinteable {
    function mint(address to, uint256 amount) external;
}

contract BTCBPMM is PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    struct PMMStorage {
        IERC20 btcb;
        IMinteable lbtc;   

        uint256 stakeLimit;
        uint256 totalStake;
        address withdrawAddress;
    }
    
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    // keccak256(abi.encode(uint256(keccak256("lombardfinance.storage.BTCBPMM")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PMM_STORAGE_LOCATION = 0x75814abe757fd1afd999e293d51fa6528839552b73d81c6cc151470e3106f500;

    error StakeLimitExceeded();
    error UnauthorizedAccount(address account);

    event StakeLimitSet(uint256 newStakeLimit);
    event WithdrawalAddressSet(address newWithdrawAddress);

    /// @dev https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __BTCBPMM_init(address _lbtc, address _btcb, address admin, uint256 _stakeLimit, address withdrawAddress) internal onlyInitializing {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        PMMStorage storage $ = _getPMMStorage();
        $.stakeLimit = _stakeLimit;
        $.withdrawAddress = withdrawAddress;
        
        $.lbtc = IMinteable(_lbtc);
        $.btcb = IERC20(_btcb);
    }

    function initialize(address _lbtc, address _btcb, address admin,uint256 _stakeLimit, address withdrawAddress) external initializer {
        __Pausable_init();
        __AccessControl_init();
        __BTCBPMM_init(_lbtc, _btcb, admin, _stakeLimit, withdrawAddress);
    }

    function swapBTCBToLBTC(uint256 amount) external whenNotPaused {
        PMMStorage storage $ = _getPMMStorage();
        if ($.totalStake + amount > $.stakeLimit) revert StakeLimitExceeded();

        $.totalStake += amount;
        $.btcb.safeTransferFrom(_msgSender(), address(this), amount);
        $.lbtc.mint(_msgSender(), amount);
    }

    function withdrawBTCB(uint256 amount) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        PMMStorage storage $ = _getPMMStorage();
        $.btcb.transfer($.withdrawAddress, amount); 
    }

    function setWithdrawalAddress(address newWithdrawAddress) external onlyRole(TIMELOCK_ROLE) {
        _getPMMStorage().withdrawAddress = newWithdrawAddress;
        emit WithdrawalAddressSet(newWithdrawAddress);
    }

    function setStakeLimit(uint256 newStakeLimit) external onlyRole(TIMELOCK_ROLE) {
        _getPMMStorage().stakeLimit = newStakeLimit;
        emit StakeLimitSet(newStakeLimit);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function stakeLimit() external view returns (uint256) {
        return _getPMMStorage().stakeLimit;
    }

    function remainingStake() external view returns (uint256) {
        PMMStorage storage $ = _getPMMStorage();
        if ($.totalStake > $.stakeLimit) return 0;
        return $.stakeLimit - $.totalStake;
    }

    function withdrawalAddress() external view returns (address) {
        return _getPMMStorage().withdrawAddress;
    }

    function _getPMMStorage() private pure returns (PMMStorage storage $) {
        assembly {
            $.slot := PMM_STORAGE_LOCATION
        }
    }
}
