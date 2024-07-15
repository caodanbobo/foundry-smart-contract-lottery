// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle private raffle;
    HelperConfig private helperConfig;

    uint256 public enteranceFee;
    uint256 public interval;
    address public vrfCoordinator;
    bytes32 public keyHash;
    uint256 public subId;
    uint32 public callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BAL = 10 ether;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffle();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();

        enteranceFee = config.enteranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        subId = config.subId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BAL);
    }

    function testRaffleInigtializedWithOpen() public view {
        assertEq(raffle.getRaffleState(), 0);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //arrange
        vm.prank(PLAYER);
        //act / asset
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordPlayerWhenTheyEnter() public {
        //arrange
        vm.prank(PLAYER);
        //act
        raffle.enterRaffle{value: enteranceFee}();
        address player1 = raffle.getPlayer(0);
        // asset
        assert(player1 == PLAYER);
    }

    function testRaffleEmitEvent() public {
        //arrange
        vm.prank(PLAYER);
        //act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        // asset
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testRaffleDontAllowPlayersToEnterWhileRaffleIsCalculating()
        public
    {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        //this will changed the time
        vm.warp(block.timestamp + interval + 1);
        //
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        //act/assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                            TEST CHECKUPKEEP
    //////////////////////////////////////////////////////////////*/

    function testCheckUpKeepReturnFalseIfNoBalance() public {
        //arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(upkeepNeeded == false);
    }

    function testCheckUpKeepReturnFalseIfStatusNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        //this will changed the time
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //assert
        assert(upkeepNeeded == false);
    }

    /*//////////////////////////////////////////////////////////////
                           TEST PERFORMUPKEEP
    //////////////////////////////////////////////////////////////*/

    function testPerformUpkeepRevertIfCheckUpKeepIsFalse() public {
        //arrage
        uint256 curBalance = 0;
        uint256 players = 0;
        uint256 rState = raffle.getRaffleState();

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                curBalance,
                players,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        //this will changed the time
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntered
    {
        //arrage

        //act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //there will be two events, first is from VRF, the second is ours,
        //inside each log, the first topic is reserved
        bytes32 requestId = entries[1].topics[1];
        assert(uint256(requestId) > 0);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST FULFILLRANDOMWORDS
    //////////////////////////////////////////////////////////////*/
    modifier skipForking() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomCanOnlyBeCallAfterPerformUpKeep(
        uint256 randomRequestId
    ) public raffleEntered skipForking {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordisPicksAWinnerResetAndSendMoney()
        public
        raffleEntered
        skipForking
    {
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: enteranceFee}();
        }
        uint256 startingTimestamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; // the requestId is set to 1
        console.log("requesuId:", uint256(requestId));

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        address recentWinner = raffle.getRecentWinner();
        uint256 rState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimestamp = raffle.getLastTimestamp();
        uint256 prize = enteranceFee * 4;

        assert(recentWinner == expectedWinner);
        assert(rState == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimestamp > startingTimestamp);
    }
}
