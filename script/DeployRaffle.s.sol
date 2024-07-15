// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubcription, AddConsumer} from "./interactions.s.sol";

contract DeployRaffle is Script {
    function run() public {}

    function deployRaffle() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();

        if (config.subId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subId, config.vrfCoordinator) = createSubscription
                .createSubscription(config.vrfCoordinator, config.account);
            FundSubcription fundSubscription = new FundSubcription();
            fundSubscription.fundSubscription(
                config.vrfCoordinator,
                config.subId,
                config.link,
                config.account
            );
        }

        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.enteranceFee,
            config.interval,
            config.vrfCoordinator,
            config.keyHash,
            config.subId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addingConsumer(
            address(raffle),
            config.vrfCoordinator,
            config.subId,
            config.account
        );

        return (raffle, helperConfig);
    }
}
