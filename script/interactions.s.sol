// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mock/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoodi = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        (uint256 subId, ) = createSubscription(vrfCoodi, account);
        return (subId, vrfCoodi);
    }

    function createSubscription(
        address vrfCoodoi,
        address account
    ) public returns (uint256, address) {
        console.log("creating sub on chain id: ", block.chainid);
        vm.startBroadcast(account);
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoodoi).createSubscription();
        vm.stopBroadcast();
        console.log("sub is: ", subId);
        return (subId, vrfCoodoi);
    }

    function run() public {
        createSubscriptionUsingConfig();
    }
}

contract FundSubcription is Script, CodeConstants {
    uint public constant FUND_AMOUT = 3 ether; //LINK

    function run() public {
        FundSubcriptionUsingConfig();
    }

    function FundSubcriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoodi = helperConfig.getConfig().vrfCoordinator;
        uint256 subId = helperConfig.getConfig().subId;
        address linkToken = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;
        fundSubscription(vrfCoodi, subId, linkToken, account);
    }

    function fundSubscription(
        address vrfCoodi,
        uint256 subId,
        address linkToken,
        address account
    ) public {
        console.log("funding sub: ", subId);
        console.log("using vrfCoodinator:", vrfCoodi);
        console.log("on chain id: ", block.chainid);
        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoodi).fundSubscription(
                subId,
                FUND_AMOUT * 100
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            LinkToken(linkToken).transferAndCall(
                vrfCoodi,
                FUND_AMOUT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }
}

contract AddConsumer is Script {
    function run() public {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addingConsumerUsingConfig(mostRecentDeployed);
    }

    function addingConsumerUsingConfig(address contractToVrf) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoodi = helperConfig.getConfig().vrfCoordinator;
        uint256 subId = helperConfig.getConfig().subId;
        address account = helperConfig.getConfig().account;
        addingConsumer(contractToVrf, vrfCoodi, subId, account);
    }

    function addingConsumer(
        address contractToVrf,
        address vrfCoodi,
        uint256 subId,
        address account
    ) public {
        console.log("adding consumer contract: ", contractToVrf);
        console.log("using vrfCoodinator:", vrfCoodi);
        console.log("on chain id: ", block.chainid);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoodi).addConsumer(subId, contractToVrf);
        vm.stopBroadcast();
    }
}
