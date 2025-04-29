// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BaseGroupFactory} from "src/base-group/BaseGroupFactory.sol";

contract CreateGroup is Script {
    address deployer = address(0xaAb15A045e74c6539B696B115e763A22BE5C9594);
    BaseGroupFactory public baseGroupFactory = BaseGroupFactory(address(0xD0B5Bd9962197BEaC4cbA24244ec3587f19Bd06d)); 

    address owner = address(0x0aFd8899bca011Bb95611409f09c8EFbf6b169cF);
    address service = address(0xA764b237d0f6e1F749C9422CA26d832d7287972e);
    address feeCollection = owner;
    address backingCondition = address(0xA88553421CED59Ff886A79855A7B9AA16417335B);
    

    function setUp() public {}

    function run() public {
        address[] memory initialConditions = new address[](1);
        initialConditions[0] = backingCondition;
        string memory name = "Circles Backers";
        string memory symbol = "CBG";
        bytes32 metadataDigest = bytes32(0);

        vm.startBroadcast(deployer);

        (address group,,) = baseGroupFactory.createBaseGroup(
            owner, 
            service, 
            feeCollection, 
            initialConditions, 
            name, 
            symbol, 
            metadataDigest
        );

        vm.stopBroadcast();
        console.log(address(group), "BaseGroup"); // 0x1ACA75e38263c79d9D4F10dF0635cc6FCfe6F026
    }
}