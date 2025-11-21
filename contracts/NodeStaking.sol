// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Credits.sol";
import "./BenefitAddress.sol";
import "./DelegatedStaking.sol";


contract NodeStaking is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private maxAccountsAllowed = 100000;
    uint256 private minStakeAmount = 400 * 10 ** 18;

    struct StakingInfo {
        address nodeAddress;
        uint stakedBalance;
        uint stakedCredits;
    }

    event NodeStaked(address indexed nodeAddress, uint stakedBalance, uint stakedCredits);
    event NodeUnstaked(address indexed nodeAddress, uint stakedBalance, uint stakedCredits);
    event NodeSlashed(address indexed nodeAddress, uint stakedBalance, uint stakedCredits);

    // store all staking info
    EnumerableSet.AddressSet private allNodeAddresses;
    mapping(address => StakingInfo) private nodeStakingMap;

    Credits private credits;
    BenefitAddress private ba;
    DelegatedStaking private ds;

    address private adminAddress;

    constructor(
        address creditsContract,
        address benefitAddressContract,
        address delegatedStakingContract
    ) Ownable(msg.sender) {
        credits = Credits(creditsContract);
        ba = BenefitAddress(benefitAddressContract);
        ds = DelegatedStaking(delegatedStakingContract);
    }

    // public api for owner
    function setAdminAddress(address addr) external onlyOwner {
        adminAddress = addr;
    }

    function setMinStakeAmount(uint stakeAmount) public onlyOwner {
        require(stakeAmount > 0, "minimum stake amount is 0");
        minStakeAmount = stakeAmount;
    }

    // public api for node
    function getMinStakeAmount() public view returns (uint) {
        return minStakeAmount;
    }
    
    function getStakingInfo(address nodeAddress) public view returns (StakingInfo memory) {
        return nodeStakingMap[nodeAddress];
    }

    function getAllNodeAddresses() public view returns (address[] memory) {
        return allNodeAddresses.values();
    }

    function stake(uint stakedAmount) public payable {
        require(allNodeAddresses.length() < maxAccountsAllowed, "Network is full");
        require(stakedAmount >= minStakeAmount, "Staked amount is too low");

        StakingInfo memory currentStakingInfo = nodeStakingMap[msg.sender];
        uint currentStakedAmount = currentStakingInfo.stakedBalance + currentStakingInfo.stakedCredits;


        if (currentStakedAmount < stakedAmount) {
            uint stakedBalance = 0;
            uint stakedCredits = 0;
            uint diff = stakedAmount - currentStakedAmount;
            uint stakableCredits = credits.getCredits(msg.sender);
            if (diff <= stakableCredits) {
                stakedCredits = diff;
                stakedBalance = 0;
            } else {
                stakedCredits = stakableCredits;
                stakedBalance = diff - stakableCredits;
            }
            require(msg.value == stakedBalance, "Inconsistent staked balance");
            credits.stakeCredits(msg.sender, stakedCredits);
            nodeStakingMap[msg.sender].stakedBalance += stakedBalance;
            nodeStakingMap[msg.sender].stakedCredits += stakedCredits;
        } else if (currentStakedAmount > stakedAmount) {
            require(msg.value == 0, "Inconsistent staked balance");
            uint diff = currentStakedAmount - stakedAmount;
            if (diff <= currentStakingInfo.stakedBalance) {
                nodeStakingMap[msg.sender].stakedBalance -= diff;
                // return the staked balance
                returnBalance(msg.sender, diff);
            } else {
                nodeStakingMap[msg.sender].stakedBalance = 0;
                nodeStakingMap[msg.sender].stakedCredits = stakedAmount;
                // return the staked balance
                if (currentStakingInfo.stakedBalance > 0) {
                    returnBalance(msg.sender, currentStakingInfo.stakedBalance);
                }
                // return the staked credits
                uint creditsDiff = diff - currentStakingInfo.stakedBalance;
                credits.unstakeCredits(msg.sender, creditsDiff);
            }
        } else {
            require(msg.value == 0, "Inconsistent staked balance");
        }

        nodeStakingMap[msg.sender].nodeAddress = msg.sender;
        allNodeAddresses.add(msg.sender);
        emit NodeStaked(msg.sender, nodeStakingMap[msg.sender].stakedBalance, nodeStakingMap[msg.sender].stakedCredits);
    }

    // public api for admin
    function unstake(address nodeAddress) public {
        require(msg.sender == adminAddress, "Not called by the admin");
        require(allNodeAddresses.contains(nodeAddress), "Not staked");
        uint stakedBalance = nodeStakingMap[nodeAddress].stakedBalance;
        uint stakedCredits = nodeStakingMap[nodeAddress].stakedCredits;
        uint stakeAmount = stakedBalance + stakedCredits;
        require(stakeAmount > 0, "Staking is zero");

        // Return the staked balance
        if (stakedBalance > 0) {
            nodeStakingMap[nodeAddress].stakedBalance = 0;
            returnBalance(nodeAddress, stakedBalance);
        }

        // Return the credits
        if (stakedCredits > 0) {
            credits.unstakeCredits(nodeAddress, stakedCredits);
        }

        // remove node
        allNodeAddresses.remove(nodeAddress);
        delete nodeStakingMap[nodeAddress];
        emit NodeUnstaked(nodeAddress, stakedBalance, stakedCredits);
    }

    function slashStaking(address nodeAddress) public {
        require(
            msg.sender == adminAddress,
            "Not called by the admin"
        );
        require(
            allNodeAddresses.contains(nodeAddress),
            "Node not staked"
        );
        uint stakedBalance = nodeStakingMap[nodeAddress].stakedBalance;
        uint stakedCredits = nodeStakingMap[nodeAddress].stakedCredits;
        uint stakeAmount = stakedBalance + stakedCredits;
        require(
            stakeAmount > 0,
            "Staking is zero"
        );
        if (stakedBalance > 0) {
            (bool success, ) = owner().call{value: stakedBalance}("");
            require(success, "Token transfer failed");
        }
        ds.slashNode(nodeAddress);
        // remove node
        allNodeAddresses.remove(nodeAddress);
        delete nodeStakingMap[nodeAddress];
        emit NodeSlashed(nodeAddress, stakedBalance, stakedCredits);
    }

    function returnBalance(address nodeAddress, uint amount) internal {
        require(amount > 0, "Amount is zero");
        address benefitAddress = ba.getBenefitAddress(nodeAddress);
        if (benefitAddress == address(0)) {
            benefitAddress = nodeAddress;
        }
        (bool success, ) = benefitAddress.call{value: amount}("");
        require(success, "Token transfer failed");
    }
}
