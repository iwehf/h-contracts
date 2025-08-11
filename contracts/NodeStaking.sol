// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Credits.sol";


contract NodeStaking is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private maxAccountsAllowed = 100000;
    uint256 private minStakeAmount = 400 * 10 ** 18;

    struct StakingInfo {
        address nodeAddress;
        uint stakedBalance;
        uint stakedCredits;
        bool isLocked;
    }

    event NodeStaked(address indexed nodeAddress, uint stakedBalance, uint stakedCredits);
    event NodeUnstaked(address indexed nodeAddress, uint stakedBalance, uint stakedCredits);
    event NodeSlashed(address indexed nodeAddress, uint stakedBalance, uint stakedCredits);

    // store all staking info
    EnumerableSet.AddressSet private allNodeAddresses;
    mapping(address => StakingInfo) private nodeStakingMap;

    Credits private credits;

    address private adminAddress;

    constructor(
        address creditsAddress
    ) Ownable(msg.sender) {
        credits = Credits(creditsAddress);
    }

    // public api for owner
    function setAdminAddress(address addr) external onlyOwner {
        adminAddress = addr;
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

    function stake(uint stakedBalance, uint stakedCredits) public payable {
        require(allNodeAddresses.length() < maxAccountsAllowed, "Network is full");
        require(!allNodeAddresses.contains(msg.sender), "Already staked");
        require(msg.value == stakedBalance, "Inconsistent staked balance");
        uint nodeCredits = credits.getCredits(msg.sender);
        require(stakedCredits <= nodeCredits, "Insufficient credits");

        uint totalStaked = stakedBalance + stakedCredits;
        require(totalStaked >= minStakeAmount, "Staked amount is too low");

        if (stakedCredits > 0) {
            credits.stakeCredits(msg.sender, stakedCredits);
        }

        nodeStakingMap[msg.sender].nodeAddress = msg.sender;
        nodeStakingMap[msg.sender].stakedBalance = stakedBalance;
        nodeStakingMap[msg.sender].stakedCredits = stakedCredits;
        nodeStakingMap[msg.sender].isLocked = false;
        allNodeAddresses.add(msg.sender);
        emit NodeStaked(msg.sender, stakedBalance, stakedCredits);
    }

    function unstake() public {
        require(allNodeAddresses.contains(msg.sender), "Not staked");
        require(!nodeStakingMap[msg.sender].isLocked, "Staking is locked");
        uint stakedBalance = nodeStakingMap[msg.sender].stakedBalance;
        uint stakedCredits = nodeStakingMap[msg.sender].stakedCredits;
        uint stakeAmount = stakedBalance + stakedCredits;
        require(stakeAmount > 0, "Staking is zero");

        // Return the staked balance
        if (stakedBalance > 0) {
            nodeStakingMap[msg.sender].stakedBalance = 0;
            (bool success, ) = msg.sender.call{value: stakedBalance}("");
            require(success, "Token transfer failed");
        }

        // Return the credits
        if (stakedCredits > 0) {
            credits.unstakeCredits(msg.sender, stakedCredits);
        }

        // remove node
        allNodeAddresses.remove(msg.sender);
        delete nodeStakingMap[msg.sender];
        emit NodeUnstaked(msg.sender, stakedBalance, stakedCredits);
    }

    // public api for admin
    function lockStaking(address nodeAddress) public {
        require(
            msg.sender == adminAddress,
            "Not called by the admin"
        );
        require(
            allNodeAddresses.contains(nodeAddress),
            "Node not staked"
        );
        uint stakeAmount = nodeStakingMap[nodeAddress].stakedBalance + nodeStakingMap[nodeAddress].stakedCredits;
        require(
            stakeAmount > 0,
            "Staking is zero"
        );
        require(
            !nodeStakingMap[nodeAddress].isLocked,
            "Staking is already locked"
        );
        nodeStakingMap[nodeAddress].isLocked = true;
    }

    function unlockStaking(address nodeAddress) public {
        require(
            msg.sender == adminAddress,
            "Not called by the admin"
        );
        require(
            allNodeAddresses.contains(nodeAddress),
            "Node not staked"
        );
        uint stakeAmount = nodeStakingMap[nodeAddress].stakedBalance + nodeStakingMap[nodeAddress].stakedCredits;
        require(
            stakeAmount > 0,
            "Staking is zero"
        );
        require(
            nodeStakingMap[nodeAddress].isLocked,
            "Staking is not locked"
        ); 
        nodeStakingMap[nodeAddress].isLocked = false;
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
        require(
            nodeStakingMap[nodeAddress].isLocked,
            "Staking is not locked"
        );
        
        // remove node
        allNodeAddresses.remove(nodeAddress);
        delete nodeStakingMap[nodeAddress];
        emit NodeSlashed(nodeAddress, stakedBalance, stakedCredits);
    }
}
