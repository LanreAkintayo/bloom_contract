// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {TypesLib} from "../../library/TypesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract JurorManager is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Juror {
        address jurorAddress;
        uint256 stakeAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/
    uint256 public minStakeAmount = 1000e18;
    uint256 public maxStakeAmount = 1_000_000_000e18;

    mapping(address => Juror) public jurors;

    IERC20 public bloomToken;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error JurorManager__ZeroAddress();
    error JurorManager__ZeroAmount();
    error JurorManager__InvalidStakeAmount();
    error JurorManager__AlreadyRegistered();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event JurorRegistered(address indexed juror, uint256 stakeAmount);
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);
    event MaxStakeAmountUpdated(uint256 newMaxStakeAmount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _bloomTokenAddress) Ownable(msg.sender) {
        if (_bloomTokenAddress == address(0)) {
            revert JurorManager__ZeroAddress();
        }
        bloomToken = IERC20(_bloomTokenAddress);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    function registerJuror(uint256 stakeAmount) external {
        if (stakeAmount < minStakeAmount || stakeAmount > maxStakeAmount) {
            revert JurorManager__InvalidStakeAmount();
        }

        if (jurors[msg.sender].stakeAmount > 0) {
            revert JurorManager__AlreadyRegistered();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // // Register juror
        jurors[msg.sender] = Juror({
            jurorAddress: msg.sender,
            stakeAmount: stakeAmount,
        });

        emit JurorRegistered(msg.sender, stakeAmount);
    }

    function stakeMore(uint256 additionalStake) external {
        if (additionalStake == 0) {
            revert JurorManager__ZeroAmount();
        }

        Juror storage juror = jurors[msg.sender];

        if (juror.jurorAddress == address(0)) {
            revert JurorManager__NotRegistered();
        }

        uint256 newStakeAmount = juror.stakeAmount + additionalStake;

        if (newStakeAmount > maxStakeAmount) {
            revert JurorManager__InvalidStakeAmount();
        }

        // Transfer Bloom tokens to this contract
        bloomToken.safeTransferFrom(msg.sender, address(this), additionalStake);

        // Update juror stake
        juror.stakeAmount = newStakeAmount;

        emit MoreStaked(msg.sender, additionalStake);
    }

    function vote(uint256 dealId) external {
        // Weighted voting will be employed here. It will be based on the stake and the reputation of the juror.

         

    }

    function updateMinStakeAmount(uint256 _minStakeAmount) external onlyOwner {
        if (_minStakeAmount == 0) {
            revert JurorManager__ZeroAmount();
        }
        minStakeAmount = _minStakeAmount;
        emit MinStakeAmountUpdated(_minStakeAmount);
    }

    function updateMaxStakeAmount(uint256 _maxStakeAmount) external onlyOwner {
        if (_maxStakeAmount == 0) {
            revert JurorManager__ZeroAmount();
        }
        maxStakeAmount = _maxStakeAmount;
        emit MaxStakeAmountUpdated(_maxStakeAmount);
    }
}
