// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/access/Ownable.sol";

contract BenefitAddress is Ownable {
    mapping(address => address) private benefitAddressMap;

    event BenefitAddressSet(address indexed nodeAddress, address indexed benefitAddress);

    constructor() Ownable(msg.sender) {
    }

    function getBenefitAddress(address nodeAddress) external view returns (address) {
        address addr = benefitAddressMap[nodeAddress];
        return addr;
    }

    function setBenefitAddress(address benefitAddress) external {
        require(benefitAddress != address(0), "Benefit address cannot be zero");
        require(benefitAddressMap[msg.sender] == address(0), "Benefit address already set");
        benefitAddressMap[msg.sender] = benefitAddress;
        emit BenefitAddressSet(msg.sender, benefitAddress);
    }
}