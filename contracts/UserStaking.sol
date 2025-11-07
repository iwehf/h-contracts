// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UserStaking is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct UserStakingInfo {
        address userAddress;
        address nodeAddress;
        uint stakeAmount;
    }

    event UserStaked(
        address indexed userAddress,
        address nodeAddress,
        uint amount
    );
    event UserUnstaked(
        address indexed userAddress,
        address nodeAddress,
        uint amount
    );
    event NodeDelegatorShareChanged(address indexed nodeAddress, uint8 share);
    event NodeSlashed(address indexed nodeAddress);

    EnumerableSet.AddressSet private availableNodes;
    mapping(address => uint8) private nodeDelegatorShare;

    mapping(bytes32 => UserStakingInfo) private stakingInfos;
    EnumerableSet.AddressSet private userAddresses;
    mapping(address => EnumerableSet.Bytes32Set) private userIndex;
    EnumerableSet.AddressSet private nodeAddresses;
    mapping(address => EnumerableSet.Bytes32Set) private nodeIndex;

    mapping(address => uint) private nodeStakeAmount;
    mapping(address => uint) private userStakeAmount;

    uint private minStakeAmount = 400 * 10 ** 18;

    address private nodeStakingAddress;

    constructor() Ownable(msg.sender) {}

    function setMinStakeAmount(uint stakeAmount) public onlyOwner {
        require(stakeAmount > 0, "minimum stake amount is 0");
        minStakeAmount = stakeAmount;
    }

    function getMinStakeAmount() public view returns (uint) {
        return minStakeAmount;
    }

    function setNodeStakingAddress(address addr) public onlyOwner {
        nodeStakingAddress = addr;
    }

    function setDelegatorShare(uint8 share) public {
        require(share < 100, "share is larger than 100");
        nodeDelegatorShare[msg.sender] = share;
        emit NodeDelegatorShareChanged(msg.sender, share);
        // withdraw all user staking on this node when the node closes user staing (set delegator share to 0)
        if (share == 0) {
            availableNodes.remove(msg.sender);
            clearStakingOfNode(msg.sender, false);
        } else {
            availableNodes.add(msg.sender);
        }
    }

    function stake(address nodeAddress, uint amount) public payable {
        require(
            nodeDelegatorShare[nodeAddress] > 0,
            "node delegator share is 0"
        );
        require(amount >= minStakeAmount, "stake amount is too low");

        bytes32 stakingInfoID = keccak256(
            abi.encodePacked(msg.sender, nodeAddress)
        );
        uint oldAmount = stakingInfos[stakingInfoID].stakeAmount;
        require(
            (amount > oldAmount && msg.value == amount - oldAmount) ||
                (amount <= oldAmount && msg.value == 0),
            "Inconsistent staked amount"
        );

        stakingInfos[stakingInfoID].userAddress = msg.sender;
        stakingInfos[stakingInfoID].nodeAddress = nodeAddress;
        stakingInfos[stakingInfoID].stakeAmount = amount;

        userIndex[msg.sender].add(stakingInfoID);
        nodeIndex[nodeAddress].add(stakingInfoID);

        userStakeAmount[msg.sender] -= oldAmount;
        userStakeAmount[msg.sender] += amount;
        nodeStakeAmount[nodeAddress] -= oldAmount;
        nodeStakeAmount[nodeAddress] += amount;

        userAddresses.add(msg.sender);
        nodeAddresses.add(nodeAddress);

        if (amount < oldAmount) {
            withdrawStaking(msg.sender, oldAmount - amount);
        }
        emit UserStaked(msg.sender, nodeAddress, amount);
    }

    function unstake(address nodeAddress) public {
        bytes32 stakingInfoID = keccak256(
            abi.encodePacked(msg.sender, nodeAddress)
        );

        require(
            stakingInfos[stakingInfoID].stakeAmount > 0,
            "no such staking info"
        );
        require(
            userIndex[msg.sender].contains(stakingInfoID),
            "no such staking info"
        );
        require(
            nodeIndex[nodeAddress].contains(stakingInfoID),
            "no such staking info"
        );

        uint amount = stakingInfos[stakingInfoID].stakeAmount;

        delete stakingInfos[stakingInfoID];
        userIndex[msg.sender].remove(stakingInfoID);
        if (userIndex[msg.sender].length() == 0) {
            userAddresses.remove(msg.sender);
        }
        nodeIndex[nodeAddress].remove(stakingInfoID);
        if (nodeIndex[nodeAddress].length() == 0) {
            nodeAddresses.remove(nodeAddress);
        }

        userStakeAmount[msg.sender] -= amount;
        nodeStakeAmount[nodeAddress] -= amount;

        // withdraw staking tokens
        withdrawStaking(msg.sender, amount);

        emit UserUnstaked(msg.sender, nodeAddress, amount);
    }

    function slashNode(address nodeAddress) public {
        require(
            msg.sender == nodeStakingAddress,
            "Not called by node staking contract"
        );
        if (nodeAddresses.contains(nodeAddress)) {
            clearStakingOfNode(nodeAddress, true);
            emit NodeSlashed(nodeAddress);
        }
    }

    function withdrawStaking(address userAddress, uint amount) private {
        require(amount > 0, "amount is 0");

        (bool success, ) = userAddress.call{value: amount}("");
        require(success, "token transfer failed");
    }

    function slashStaking(uint amount) private {
        require(amount > 0, "amount is 0");

        (bool success, ) = owner().call{value: amount}("");
        require(success, "token transfer failed");
    }

    function clearStakingOfNode(address nodeAddress, bool slash) private {
        bytes32[] memory stakingInfoIDs = nodeIndex[nodeAddress].values();
        for (uint i = 0; i < stakingInfoIDs.length; i++) {
            bytes32 stakingInfoID = stakingInfoIDs[i];
            address userAddress = stakingInfos[stakingInfoID].userAddress;
            uint amount = stakingInfos[stakingInfoID].stakeAmount;
            userIndex[userAddress].remove(stakingInfoID);
            if (userIndex[userAddress].length() == 0) {
                userAddresses.remove(userAddress);
            }
            userStakeAmount[userAddress] -= amount;
            nodeIndex[nodeAddress].remove(stakingInfoID);
            if (slash) {
                slashStaking(amount);
            } else {
                withdrawStaking(userAddress, amount);
            }
            delete stakingInfos[stakingInfoID];
        }
        nodeAddresses.remove(nodeAddress);
        delete nodeStakeAmount[nodeAddress];
    }

    function getNodeDelegatorShare(
        address nodeAddress
    ) public view returns (uint8) {
        return nodeDelegatorShare[nodeAddress];
    }

    function getAllNodeDelegatorShares()
        public
        view
        returns (address[] memory, uint8[] memory)
    {
        address[] memory nodes = availableNodes.values();
        uint8[] memory shares = new uint8[](nodes.length);
        for (uint i = 0; i < nodes.length; i++) {
            shares[i] = nodeDelegatorShare[nodes[i]];
        }
        return (nodes, shares);
    }

    function getUserStakingAmount(
        address userAddress,
        address nodeAddress
    ) public view returns (uint) {
        bytes32 stakingInfoID = keccak256(
            abi.encodePacked(userAddress, nodeAddress)
        );
        uint amount = stakingInfos[stakingInfoID].stakeAmount;
        return amount;
    }

    function getNodeStakingInfos(
        address nodeAddress
    ) public view returns (address[] memory, uint[] memory) {
        uint length = nodeIndex[nodeAddress].length();

        address[] memory addresses = new address[](length);
        uint[] memory amounts = new uint[](length);

        for (uint i = 0; i < length; i++) {
            bytes32 stakingInfoID = nodeIndex[nodeAddress].at(i);
            addresses[i] = stakingInfos[stakingInfoID].userAddress;
            amounts[i] = stakingInfos[stakingInfoID].stakeAmount;
        }
        return (addresses, amounts);
    }

    function getUserStakingInfos(
        address userAddress
    ) public view returns (address[] memory, uint[] memory) {
        uint length = userIndex[userAddress].length();

        address[] memory addresses = new address[](length);
        uint[] memory amounts = new uint[](length);

        for (uint i = 0; i < length; i++) {
            bytes32 stakingInfoID = userIndex[userAddress].at(i);
            addresses[i] = stakingInfos[stakingInfoID].nodeAddress;
            amounts[i] = stakingInfos[stakingInfoID].stakeAmount;
        }
        return (addresses, amounts);
    }

    function getNodeStakeAmount(
        address nodeAddress
    ) public view returns (uint) {
        return nodeStakeAmount[nodeAddress];
    }

    function getUserStakeAmount(
        address userAddress
    ) public view returns (uint) {
        return userStakeAmount[userAddress];
    }

    function getAllUserAddresses() public view returns (address[] memory) {
        return userAddresses.values();
    }

    function getAllNodeAddresses() public view returns (address[] memory) {
        return nodeAddresses.values();
    }
}
