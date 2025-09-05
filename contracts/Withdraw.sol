// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/access/Ownable.sol";

contract Withdraw is Ownable {
    address private withdrawalFeeAddress;

    constructor() Ownable(msg.sender) {
    }

    function setWithdrawalFeeAddress(address addr) public onlyOwner {
        withdrawalFeeAddress = addr;
    }

    function getWithdrawalFeeAddress() public view returns (address) {
        return withdrawalFeeAddress;
    }

    function withdraw(address to, uint256 amount, uint256 withdrawalFeeAmount) public payable {
        require(amount > 0, "Amount is zero");
        require(to != address(0), "To address is zero");
        require(withdrawalFeeAmount > 0, "Withdrawal fee amount is zero");
        require(msg.value == amount + withdrawalFeeAmount, "Withdrawal fee amount is not equal to the amount");

        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdraw token transfer failed");
        (bool success1, ) = withdrawalFeeAddress.call{value: withdrawalFeeAmount}("");
        require(success1, "Withdrawal fee token transfer failed");
    }
}