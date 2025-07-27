// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/* solhint-disable no-console */

import "forge-std/Test.sol";
import "src/SplitNFTFactory.sol";
import {ISplitERC721Errors} from "src/ISplitERC721Errors.sol";
import {MockERC721} from "./MockERC721.sol";

contract SplitNFTFactoryTest is Test {
    // Constants for testing
    // These addresses are derived from a keccak256 hash to ensure uniqueness in the test environment
    address public constant NFT_OWNER = address(uint160(uint256(keccak256("NFT_OWNER"))));
    address public constant ANOTHER_ADDRESS = address(uint160(uint256(keccak256("ANOTHER_ADDRESS"))));
    // Example token ID for testing purposes
    uint256 public constant TOKEN_ID = 42;

    // Contracts used in the tests
    // MockERC721 is a mock implementation of an ERC721 token for testing purposes
    MockERC721 public mockNFT;
    // SplitNFTFactory is the contract under test
    SplitNFTFactory public splitNFTFactory;

    /**
     * @dev Set up the test environment.
     * This function initializes the MockERC721 contract and mints an NFT to the NFT_OWNER.
     * It also deploys the SplitERC721 contract for testing.
     */
    function setUp() public {
        mockNFT = new MockERC721({name: "MockToken", symbol: "MTK", _baseURI: "[SOME_BASE_URI]/"});
        mockNFT.mint(NFT_OWNER, TOKEN_ID);
        splitNFTFactory = new SplitNFTFactory();
    }

    /**
     * @dev Test to verify that the factory can successfully create a split NFT contract.
     * This test covers the complete flow from NFT approval through split creation,
     * ensuring all components work together correctly.
     *
     * Test scenario:
     * 1. NFT owner approves the factory to transfer their NFT
     * 2. Call splitNFT() to create fractionalized tokens
     * 3. Verify a new contract was created and tracked
     * 4. Verify the NFT was transferred to the new contract
     * 5. Verify split tokens were minted to the caller
     *
     * This validates the core factory functionality and integration with SplitERC721.
     */
    function test_canCreateSplitNFT() public {
        // Arrange
        uint24 numSplits = 100;

        // NFT owner approves factory to transfer the NFT
        vm.prank(NFT_OWNER);
        mockNFT.approve(address(splitNFTFactory), TOKEN_ID);

        // Act - Create split NFT
        vm.prank(NFT_OWNER);
        address splitAddress = splitNFTFactory.splitNFT(address(mockNFT), TOKEN_ID, numSplits);

        // Assert - Verify contract creation and tracking
        assertEq(splitNFTFactory.splitNFTContractsCount(), 1, "Should have created one split contract");
        assertEq(splitNFTFactory.splitNFTs(0), splitAddress, "Should store split contract at index 0");

        // Verify NFT was transferred to the split contract
        assertEq(mockNFT.ownerOf(TOKEN_ID), splitAddress, "Split contract should own the NFT");

        // Verify split tokens were minted to the caller
        SplitERC721 splitContract = SplitERC721(splitAddress);
        assertEq(splitContract.balanceOf(NFT_OWNER, 0), numSplits, "Caller should receive all split tokens");

        // Verify the escrowed NFT data is correctly set
        (address tokenContract, uint256 tokenId, uint24 totalSplits, uint64 escrowTimestamp, uint64 redeemTimestamp) =
            splitContract.splitNFT();
        assertEq(tokenContract, address(mockNFT), "Should store correct token contract");
        assertEq(tokenId, TOKEN_ID, "Should store correct token ID");
        assertEq(totalSplits, numSplits, "Should store correct split count");
        assertGt(escrowTimestamp, 0, "Should set escrow timestamp");
        assertEq(redeemTimestamp, 0, "Redeem timestamp should be zero");
    }

    /**
     * @dev Test to verify that multiple split contracts can be created and are properly tracked.
     */
    function test_canCreateMultipleSplitContracts() public {
        // Create multiple NFTs and split them
        uint256 TOKEN_ID_2 = 100;
        mockNFT.mint(NFT_OWNER, TOKEN_ID_2);

        vm.startPrank(NFT_OWNER);
        mockNFT.approve(address(splitNFTFactory), TOKEN_ID);
        mockNFT.approve(address(splitNFTFactory), TOKEN_ID_2);

        address split1 = splitNFTFactory.splitNFT(address(mockNFT), TOKEN_ID, 50);
        address split2 = splitNFTFactory.splitNFT(address(mockNFT), TOKEN_ID_2, 75);
        vm.stopPrank();

        // Verify both contracts are tracked correctly
        assertEq(splitNFTFactory.splitNFTContractsCount(), 2, "Should have two contracts");
        assertEq(splitNFTFactory.splitNFTs(0), split1, "First contract at index 0");
        assertEq(splitNFTFactory.splitNFTs(1), split2, "Second contract at index 1");
        assertTrue(split1 != split2, "Contracts should be different addresses");
    }

    /**
     * @dev Test to verify that the implementation address is correctly set during deployment.
     */
    function test_implementationAddressIsSet() public {
        address implementation = splitNFTFactory.SPLIT_NFT_IMPLEMENTATION();
        assertTrue(implementation != address(0), "Implementation should not be zero address");

        // Verify it's actually a SplitERC721 contract by checking constants
        SplitERC721 impl = SplitERC721(implementation);
        assertEq(impl.MIN_SPLITS(), 2, "Should have correct MIN_SPLITS");
        assertEq(impl.MAX_SPLITS(), 1e6, "Should have correct MAX_SPLITS");
    }

    /**
     * @dev Test that errors from the underlying SplitERC721 contract are properly propagated.
     */
    function test_propagatesErrorsFromSplitContract() public {
        vm.prank(NFT_OWNER);
        mockNFT.approve(address(splitNFTFactory), TOKEN_ID);

        // Try to create splits with invalid count (too high)
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.InvalidNumberOfSplits.selector,
                2000000 // Way above MAX_SPLITS
            )
        );
        vm.prank(NFT_OWNER);
        splitNFTFactory.splitNFT(address(mockNFT), TOKEN_ID, 2000000);
    }
}
