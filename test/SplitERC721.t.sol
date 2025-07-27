// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/* solhint-disable no-console */

import "forge-std/Test.sol";
import "src/SplitERC721.sol";
import {ISplitERC721Errors} from "src/ISplitERC721Errors.sol";
import {MockERC721} from "./MockERC721.sol";

contract SplitERC721Test is Test {
    // Constants for testing
    // These addresses are derived from a keccak256 hash to ensure uniqueness in the test environment
    address public constant NFT_OWNER = address(uint160(uint256(keccak256("NFT_OWNER"))));
    address public constant ANOTHER_ADDRESS = address(uint160(uint256(keccak256("ANOTHER_ADDRESS"))));
    // Example token ID for testing purposes
    uint256 public constant TOKEN_ID = 42;

    // Contracts used in the tests
    // MockERC721 is a mock implementation of an ERC721 token for testing purposes
    MockERC721 public mockNFT;
    // SplitERC721 is the contract under test, which handles the splitting of ERC721 tokens
    SplitERC721 public splitERC721;

    /**
     * @dev Set up the test environment.
     * This function initializes the MockERC721 contract and mints an NFT to the NFT_OWNER.
     * It also deploys the SplitERC721 contract for testing.
     */
    function setUp() public {
        mockNFT = new MockERC721({name: "MockToken", symbol: "MTK", _baseURI: "[SOME_BASE_URI]/"});
        mockNFT.mint(NFT_OWNER, TOKEN_ID);
        splitERC721 = new SplitERC721();
    }

    /**
     * @dev Test to verify that an NFT can be successfully transferred to the SplitERC721 contract.
     * This is a foundational test that ensures the contract can properly receive ERC721 tokens
     * through the safeTransferFrom mechanism, which is essential for the splitting functionality.
     *
     * Test scenario:
     * 1. NFT_OWNER approves ANOTHER_ADDRESS to transfer TOKEN_ID
     * 2. ANOTHER_ADDRESS transfers the NFT from NFT_OWNER to the SplitERC721 contract
     * 3. Verify that the SplitERC721 contract is now the owner of the NFT
     *
     * This test validates the basic ERC721 receiver functionality and ensures the contract
     * can accept NFT deposits as the first step in the splitting process.
     */
    function test_canReceiveNFTTransfer() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.approve(ANOTHER_ADDRESS, TOKEN_ID);

        // Act
        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Assert
        assertEq(mockNFT.ownerOf(TOKEN_ID), address(splitERC721), "NFT should be transferred to SplitERC721 contract");
        vm.stopPrank();
    }

    /**
     * @dev Test to verify the initial state of the SplitERC721 contract before any NFTs are escrowed.
     * This test ensures that the contract starts with a clean slate and all storage variables
     * are properly initialized to their expected default values.
     *
     * Test scenario:
     * 1. Query the splitNFT storage without any prior interactions
     * 2. Verify all fields return their expected zero/default values
     *
     * This test is crucial for ensuring:
     * - No residual data from previous deployments or tests
     * - Proper contract initialization
     * - Baseline state verification before testing other functionality
     */
    function test_initialStateIsEmpty() public {
        (address tokenContract, uint256 tokenId, uint24 totalSplits, uint64 escrowTimestamp, uint64 redeemTimestamp) =
            splitERC721.splitNFT();
        address escrower = splitERC721.escrower();
        assertEq(tokenContract, address(0), "Initial tokenContract should be zero address");
        assertEq(tokenId, 0, "Initial tokenId should be zero");
        assertEq(totalSplits, 0, "Initial totalSplits should be zero");
        assertEq(escrowTimestamp, 0, "Initial escrowTimestamp should be zero");
        assertEq(redeemTimestamp, 0, "Initial redeemTimestamp should be zero");
        assertEq(escrower, address(0), "Initial escrower should be zero address");
    }

    /**
     * @dev Test to verify that NFT data is correctly recorded when an NFT is transferred to the contract.
     * This test ensures that the SplitERC721 contract properly captures and stores all relevant
     * information about the escrowed NFT, including contract address, token ID, and timestamps.
     *
     * Test scenario:
     * 1. Set a specific timestamp using vm.warp() for predictable testing
     * 2. Approve and transfer an NFT to the SplitERC721 contract
     * 3. Verify that all splitNFT storage fields are correctly populated:
     *    - tokenContract matches the source NFT contract
     *    - tokenId matches the transferred token
     *    - escrowTimestamp reflects the transfer time
     *    - Other fields remain at expected initial values
     *
     * This test validates the core data integrity of the escrow mechanism and ensures
     * proper tracking of the escrowed asset for future splitting operations.
     */
    function test_recordsNFTDataOnEscrow() public {
        // Arrange
        uint256 timestamp = 1234567890; // Example timestamp for testing
        vm.warp(timestamp); // Simulate time passage for timestamp
        vm.prank(NFT_OWNER);
        mockNFT.approve(ANOTHER_ADDRESS, TOKEN_ID);

        // Act
        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Assert
        (address tokenContract, uint256 tokenId, uint24 totalSplits, uint64 escrowTimestamp, uint64 redeemTimestamp) =
            splitERC721.splitNFT();
        address escrower = splitERC721.escrower();
        assertEq(tokenContract, address(mockNFT), "Token contract should match the mock NFT contract");
        assertEq(tokenId, TOKEN_ID, "Escrowed NFT token ID should match the transferred token ID");
        assertEq(totalSplits, 0, "Total splits should be zero after transfer");
        assertEq(escrowTimestamp, uint64(timestamp), "Escrow timestamp should match the simulated timestamp");
        assertEq(redeemTimestamp, 0, "Redeem timestamp should be zero after transfer");
        assertEq(escrower, ANOTHER_ADDRESS, "Escrower should be the address that performed the NFT transfer");
    }

    /**
     * @dev Test to verify that the SplitERC721 contract rejects any additional NFT transfers after the first.
     * This test ensures that the contract enforces the single-NFT-per-contract constraint by reverting
     * with AlreadyEscrowed error when attempting to transfer a second NFT while one was previously escrowed.
     *
     * Test scenario:
     * 1. Mint and transfer the first NFT to the SplitERC721 contract successfully
     * 2. Attempt to transfer a second NFT to the same contract
     * 3. Verify that the second transfer reverts with the expected AlreadyEscrowed error
     *
     * This behavior is critical to prevent multiple NFTs from being mixed up in the same
     * splitting operation and ensures clear ownership tracking.
     */
    function test_enforcesOneNFTLimit() public {
        // Arrange
        uint256 ANOTHER_TOKEN_ID = 100; // Another token ID for testing
        mockNFT.mint(NFT_OWNER, ANOTHER_TOKEN_ID); // Mint the second NFT
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act & Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.SplitERC721Error.selector, ISplitERC721Errors.ErrorCode.AlreadyEscrowed
            )
        );
        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), ANOTHER_TOKEN_ID);
    }

    /**
     * @dev Test to verify that a SplitERC721 contract cannot be reused for a different NFT after redeeming the original.
     * This test ensures that each SplitERC721 contract instance is permanently bound to the first NFT
     * it processes, preventing reuse even after the original NFT has been redeemed/withdrawn.
     *
     * Test scenario:
     * 1. Set up approvals for transferring multiple NFTs
     * 2. Transfer the first NFT (TOKEN_ID) to the SplitERC721 contract
     * 3. Simulate redemption by transferring the first NFT back to the original owner
     * 4. Attempt to transfer a different NFT (ANOTHER_TOKEN_ID) to the same contract
     * 5. Verify that the second transfer reverts with AlreadyEscrowed error
     *
     * This behavior is critical for:
     * - Preventing contract state confusion between different NFTs
     * - Ensuring split token authenticity (each split token set corresponds to exactly one original NFT)
     * - Maintaining clear audit trails and preventing reuse attacks
     * - Enforcing the one-contract-per-NFT design principle
     */
    function test_cannotReuseContractForDifferentNFT() public {
        // Arrange
        uint256 ANOTHER_TOKEN_ID = 100; // Another token ID for testing
        mockNFT.mint(NFT_OWNER, ANOTHER_TOKEN_ID); // Mint the second NFT
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(address(splitERC721));
        mockNFT.safeTransferFrom(address(splitERC721), NFT_OWNER, TOKEN_ID);

        // Act & Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.SplitERC721Error.selector, ISplitERC721Errors.ErrorCode.AlreadyEscrowed
            )
        );
        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), ANOTHER_TOKEN_ID);
    }

    // ----------------------------- SPLIT ---------------------------

    /**
     * @dev Test to verify that only the address that deposited the NFT can mint split tokens.
     * This test ensures proper access control by restricting the split() function to the
     * "escrower" - the address that actually transferred the NFT to the contract, which
     * may be different from the original NFT owner.
     *
     * Test scenario:
     * 1. NFT_OWNER approves ANOTHER_ADDRESS to transfer TOKEN_ID
     * 2. ANOTHER_ADDRESS transfers the NFT to SplitERC721 (becomes the escrower)
     * 3. Verify NFT_OWNER cannot call split() (should revert with OnlyEscrower)
     * 4. Verify ANOTHER_ADDRESS can successfully call split()
     *
     * This access control prevents unauthorized splitting and ensures only the party
     * who initiated the escrow can control the splitting process.
     */
    function test_onlyNFTDepositorCanMintSplits() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 splits = 100; // Some test value for the split call

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act & Assert
        // Assert revert with another caller
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.SplitERC721Error.selector, ISplitERC721Errors.ErrorCode.OnlyEscrower
            )
        );
        vm.prank(NFT_OWNER);
        splitERC721.split(splits, NFT_OWNER);
        // Assert success with escrower - the same address that transferred the NFT
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, NFT_OWNER);
        assertEq(splitERC721.balanceOf(NFT_OWNER, 0), splits, "Split tokens should be minted");
    }

    /**
     * @dev Test to verify that split tokens cannot be minted to the zero address.
     * This test ensures proper input validation by rejecting invalid recipients
     * while confirming that valid addresses can receive split tokens normally.
     *
     * Test scenario:
     * 1. Set up NFT escrow with ANOTHER_ADDRESS as the depositor
     * 2. Attempt to split tokens to address(0) - should revert with InvalidRecipient
     * 3. Split tokens to a valid address - should succeed
     * 4. Verify the tokens were actually minted to the recipient
     *
     * This validation prevents tokens from being lost to the zero address and
     * ensures the splitting mechanism works correctly for valid recipients.
     */
    function test_cannotMintSplitsToZeroAddress() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 splits = 100; // Some test value for the split call
        address recipient = makeAddr("splitRecipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act & Assert
        // Assert revert with zero address
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.SplitERC721Error.selector, ISplitERC721Errors.ErrorCode.InvalidRecipient
            )
        );
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, address(0));
        // Assert success with a non-zero address
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, recipient);
        assertEq(splitERC721.balanceOf(recipient, 0), splits, "Split tokens should be minted");
    }

    /**
     * @dev Fuzz test to verify that all values within the valid splits range can be minted successfully.
     *
     * This fuzz test automatically generates random uint24 values and validates that every value
     * within [MIN_SPLITS, MAX_SPLITS] can be successfully processed by the split() function.
     * Fuzz testing is particularly valuable here because it tests edge cases and boundary
     * conditions that might not be covered in traditional unit tests.
     *
     * Test behavior:
     * - Generates random uint24 values (0 to 16,777,215)
     * - Filters to only test values within the valid range using vm.assume()
     * - Verifies successful minting for each valid splits value
     * - Confirms the exact number of tokens are minted to the recipient
     *
     * Edge cases this catches:
     * - Boundary values (MIN_SPLITS and MAX_SPLITS themselves)
     * - Random intermediate values that manual tests might miss
     * - Potential overflow/underflow issues in calculations
     * - Gas consumption patterns across the valid range
     */
    function testFuzz_validSplitsSucceed(uint24 splits) public {
        vm.assume(splits >= splitERC721.MIN_SPLITS() && splits <= splitERC721.MAX_SPLITS());

        // Setup
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act & Assert
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, NFT_OWNER);
        assertEq(splitERC721.balanceOf(NFT_OWNER, 0), splits);
    }

    /**
     * @dev Fuzz test to verify that all values outside the valid splits range are properly rejected.
     *
     * This fuzz test ensures robust input validation by testing the contract's behavior
     * with invalid split values across the entire uint24 range. It complements the valid
     * range test by focusing on proper error handling for out-of-bounds inputs.
     *
     * Test behavior:
     * - Generates random uint24 values (0 to 16,777,215)
     * - Filters to only test values outside [MIN_SPLITS, MAX_SPLITS] using vm.assume()
     * - Verifies that each invalid value triggers the expected revert
     * - Confirms the correct error code and parameters are returned
     *
     * Edge cases this catches:
     * - Values just below MIN_SPLITS (like MIN_SPLITS - 1)
     * - Values just above MAX_SPLITS (like MAX_SPLITS + 1)
     * - Extreme values (0, type(uint24).max)
     * - Ensures no invalid values accidentally pass validation
     */
    function testFuzz_invalidSplitsRevert(uint24 splits) public {
        vm.assume(splits < splitERC721.MIN_SPLITS() || splits > splitERC721.MAX_SPLITS());

        // Setup
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(ISplitERC721Errors.InvalidNumberOfSplits.selector, splits));
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, NFT_OWNER);
    }

    /**
     * @dev Test to verify that split() cannot be called multiple times on the same escrowed NFT.
     * This test ensures that once an NFT has been split into tokens, no additional splits
     * can be created, preventing inflation of the token supply and maintaining the 1:1
     * relationship between the original NFT and its total split tokens.
     *
     * Test scenario:
     * 1. Set up NFT escrow with ANOTHER_ADDRESS as the depositor
     * 2. Successfully call split() to create initial split tokens
     * 3. Attempt to call split() again with any parameters
     * 4. Verify the second call reverts with AlreadySplit error
     * 5. Confirm the original split state remains unchanged
     *
     * This protection is critical for:
     * - Preventing token supply inflation
     * - Maintaining economic integrity of the splitting mechanism
     * - Ensuring each NFT can only be fractionalized once per contract instance
     */
    function test_cannotSplitTwice() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 firstSplits = 100;
        uint24 secondSplits = 50; // Different value to test it's not parameter-dependent

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // First split succeeds
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(firstSplits, NFT_OWNER);

        // Act & Assert - Second split should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.SplitERC721Error.selector, ISplitERC721Errors.ErrorCode.AlreadySplit
            )
        );
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(secondSplits, ANOTHER_ADDRESS);

        // Verify state unchanged
        assertEq(splitERC721.balanceOf(NFT_OWNER, 0), firstSplits, "Original splits should remain");
        assertEq(splitERC721.balanceOf(ANOTHER_ADDRESS, 0), 0, "No new splits should be minted");
        (,, uint24 totalSplits,,) = splitERC721.splitNFT();
        assertEq(totalSplits, firstSplits, "Total splits should remain unchanged");
    }

    /**
     * @dev Test to verify that split() fails if the escrowed NFT is not owned by the contract.
     * This test ensures the contract validates actual NFT ownership before minting splits,
     * which is crucial for the integrity of the whole system.
     *
     * Test scenario:
     * 1. Set up normal NFT escrow with ANOTHER_ADDRESS as the depositor
     * 2. Manually transfer the NFT out of the contract (simulating theft/bug/admin action)
     * 3. Attempt to call split() on the "escrowed" NFT
     * 4. Verify it reverts with NotEscrowed error containing correct contract and token ID
     *
     * This validation is critical for:
     * - Preventing split token creation without backing NFT
     * - Detecting if the NFT was improperly removed from escrow
     * - Maintaining the integrity of the 1:1 NFT-to-splits relationship
     * - Protecting users from receiving worthless split tokens
     */
    function test_cannotSplitIfNFTNotOwnedByContract() public {
        // Arrange - Normal setup
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 splits = 100;

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Verify NFT is properly escrowed
        assertEq(mockNFT.ownerOf(TOKEN_ID), address(splitERC721), "NFT should be escrowed");

        // Simulate NFT being transferred out (could happen due to bug/exploit/admin action)
        vm.prank(address(splitERC721));
        mockNFT.safeTransferFrom(address(splitERC721), NFT_OWNER, TOKEN_ID);

        // Verify NFT is no longer in the contract
        assertEq(mockNFT.ownerOf(TOKEN_ID), NFT_OWNER, "NFT should no longer be in contract");

        // Act & Assert - Split should fail with NotEscrowed error
        vm.expectRevert(abi.encodeWithSelector(ISplitERC721Errors.NotEscrowed.selector, address(mockNFT), TOKEN_ID));
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, NFT_OWNER);

        // Verify no splits were minted
        assertEq(splitERC721.balanceOf(NFT_OWNER, 0), 0, "No splits should be minted");
        (,, uint24 totalSplits,,) = splitERC721.splitNFT();
        assertEq(totalSplits, 0, "Total splits should remain zero");
    }

    /**
     * @dev Test to verify that split tokens are correctly minted to the specified recipient.
     * This test explicitly focuses on the token minting behavior to ensure splits
     * are delivered to the intended address rather than the escrower or contract.
     *
     * Test scenario:
     * 1. Set up NFT escrow with ANOTHER_ADDRESS as the depositor
     * 2. Call split() with NFT_OWNER as the recipient (different from escrower)
     * 3. Verify tokens are minted to the specified recipient, not the escrower
     * 4. Verify other addresses have zero balance
     *
     * This ensures the recipient parameter is properly respected and tokens
     * don't accidentally go to the wrong address.
     */
    function test_splitsAreMinteToCorrectRecipient() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 splits = 100;
        address recipient = makeAddr("recipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act
        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, recipient);

        // Assert - Verify correct recipient has the tokens
        assertEq(splitERC721.balanceOf(recipient, 0), splits, "Recipient should receive all splits");
        assertEq(splitERC721.balanceOf(ANOTHER_ADDRESS, 0), 0, "Escrower should have no splits");
        assertEq(splitERC721.balanceOf(NFT_OWNER, 0), 0, "Original owner should have no splits");
        assertEq(splitERC721.balanceOf(address(splitERC721), 0), 0, "Contract should have no splits");
    }

    /**
     * @dev Test to verify that the NFTFractionalized event is correctly emitted when splitting an NFT.
     * This test ensures that external systems can properly track and respond to fractionalization
     * events through the emitted event data.
     *
     * The event is critical for:
     * - Off-chain indexing and monitoring systems
     * - Front-end applications tracking split creation
     * - Analytics and reporting tools
     * - Integration with other protocols
     */
    function test_emitsNFTFractionalizedEvent() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 splits = 100;

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Act & Assert - Expect the event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit ISplitERC721.NFTFractionalized({nftContract: address(mockNFT), tokenId: TOKEN_ID, splits: splits});

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, NFT_OWNER);
    }

    // ---------------------------- REDEEM ---------------------------

    /**
     * @dev Test to verify that redeem() fails when called on a contract with no escrowed NFT.
     * This test ensures that the redeem function properly validates that an NFT has been
     * escrowed before allowing redemption attempts.
     *
     * Test scenario:
     * 1. Call redeem() on a fresh contract that never received an NFT
     * 2. Verify it reverts with NotEscrowed error using the default empty state values
     *
     * This validation prevents:
     * - Attempting to redeem from empty contracts
     * - Confusion about contract state
     * - Potential undefined behavior with zero-initialized values
     */
    function test_cannotRedeemWithoutEscrowedNFT() public {
        // Act & Assert - Try to redeem on fresh contract (no NFT ever escrowed)
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.NotEscrowed.selector,
                address(0), // tokenContract will be zero address
                0 // tokenId will be zero
            )
        );
        splitERC721.redeem();
    }

    /**
     * @dev Test to verify that redeem() fails when called after the NFT that has already been redeemed.
     * This test ensures that the redemption process can only happen once, preventing double-redemption
     * attempts and maintaining state integrity.
     *
     * Test scenario:
     * 1. Set up NFT escrow and split into tokens
     * 2. Successfully redeem the NFT (sets redeemTimestamp)
     * 3. Attempt to call redeem() again on the same contract
     * 4. Verify it reverts with AlreadyRedeemed error
     *
     * This validation prevents:
     * - Double-redemption attempts
     * - Confusion about the contract's redemption state
     * - Potential exploits involving multiple redemption calls
     */
    function test_15_cannotRedeemAlreadyRedeemedNFT() public {
        // Arrange - Set up escrow and split
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 splits = 100;
        address recipient = makeAddr("recipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(splits, recipient);

        // First redemption should succeed
        vm.prank(recipient);
        splitERC721.redeem();

        // Verify NFT was returned and state updated
        assertEq(mockNFT.ownerOf(TOKEN_ID), recipient, "NFT should be with redeemer");
        (,,,, uint64 redeemTimestamp) = splitERC721.splitNFT();
        assertGt(redeemTimestamp, 0, "Redeem timestamp should be set");

        // Act & Assert - Second redemption should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.SplitERC721Error.selector, ISplitERC721Errors.ErrorCode.AlreadyRedeemed
            )
        );
        vm.prank(recipient);
        splitERC721.redeem();
    }

    /**
     * @dev Fuzz test to verify that redeem() fails when the caller doesn't own all split tokens.
     * This test ensures that redemption requires 100% ownership of splits by testing
     * various scenarios where some splits have been transferred to other addresses.
     *
     * Test behavior:
     * - Generates random amounts of splits to transfer away (1 to totalSplits)
     * - Verifies that any partial ownership prevents redemption
     * - Confirms the error includes correct balance and required amounts
     *
     * Test scenario:
     * 1. Set up NFT escrow and split into tokens
     * 2. Transfer a random number of splits to another address
     * 3. Attempt to redeem with remaining (incomplete) splits
     * 4. Verify it reverts with NotEnoughSplits showing actual vs required balance
     *
     * This validation ensures:
     * - 100% split ownership requirement for redemption
     * - Protection against partial redemption attempts
     * - Clear error messaging showing the shortfall
     */
    function testFuzz_cannotRedeemWithPartialSplits(uint24 transferAmount) public {
        // Arrange - Set up escrow and split
        uint24 totalSplits = 100;
        vm.assume(transferAmount > 0 && transferAmount <= totalSplits);

        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        address recipient = makeAddr("recipient");
        address otherHolder = makeAddr("otherHolder");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(totalSplits, recipient);

        // Transfer some splits away, leaving recipient with incomplete set
        vm.prank(recipient);
        splitERC721.safeTransferFrom(recipient, otherHolder, 0, transferAmount, "");

        uint24 remainingBalance = totalSplits - transferAmount;

        // Verify the setup
        assertEq(splitERC721.balanceOf(recipient, 0), remainingBalance, "Recipient should have partial splits");
        assertEq(splitERC721.balanceOf(otherHolder, 0), transferAmount, "Other holder should have transferred splits");

        // Act & Assert - Redemption should fail with correct error parameters
        vm.expectRevert(
            abi.encodeWithSelector(
                ISplitERC721Errors.NotEnoughSplits.selector,
                remainingBalance, // actual balance
                totalSplits // required balance
            )
        );
        vm.prank(recipient);
        splitERC721.redeem();
    }

    /**
     * @dev Test to verify that all split tokens are properly burnt during redemption.
     * This test focuses specifically on the burning mechanism by checking the redeemer's
     * balance before and after the redemption process.
     *
     * Test scenario:
     * 1. Set up NFT escrow and split into tokens
     * 2. Record redeemer's split balance before redemption
     * 3. Perform redemption
     * 4. Verify redeemer's split balance is zero after redemption
     *
     * This validates that the _burn() function is correctly called with the full balance.
     */
    function test_allSplitsAreBurntOnRedeem() public {
        // Arrange - Set up escrow and split
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 totalSplits = 100;
        address recipient = makeAddr("recipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(totalSplits, recipient);

        // Record balance before redemption
        uint256 balanceBefore = splitERC721.balanceOf(recipient, 0);
        assertEq(balanceBefore, totalSplits, "Should have all splits before redemption");

        // Act - Redeem the NFT
        vm.prank(recipient);
        splitERC721.redeem();

        // Assert - Verify all splits are burnt
        uint256 balanceAfter = splitERC721.balanceOf(recipient, 0);
        assertEq(balanceAfter, 0, "Should have zero splits after redemption");
    }

    /**
     * @dev Test to verify that the original NFT is correctly transferred to the redeemer.
     * This test focuses specifically on the NFT transfer mechanism during redemption,
     * ensuring the escrowed NFT is returned to the caller.
     *
     * Test scenario:
     * 1. Set up NFT escrow and split into tokens
     * 2. Verify the contract owns the NFT before redemption
     * 3. Perform redemption
     * 4. Verify the redeemer now owns the original NFT
     *
     * This validates that the safeTransferFrom() call correctly returns the NFT.
     */
    function test_originalNFTIsTransferredToRedeemer() public {
        // Arrange - Set up escrow and split
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 totalSplits = 100;
        address recipient = makeAddr("recipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(totalSplits, recipient);

        // Verify contract owns NFT before redemption
        assertEq(mockNFT.ownerOf(TOKEN_ID), address(splitERC721), "Contract should own NFT before redemption");

        // Act - Redeem the NFT
        vm.prank(recipient);
        splitERC721.redeem();

        // Assert - Verify redeemer now owns the original NFT
        assertEq(mockNFT.ownerOf(TOKEN_ID), recipient, "Redeemer should own NFT after redemption");
    }

    /**
     * @dev Test to verify that the redeemTimestamp is correctly set when redeeming the NFT.
     * This test focuses specifically on the timestamp recording mechanism during redemption,
     * ensuring accurate tracking of when the redemption occurred.
     *
     * Test scenario:
     * 1. Set up NFT escrow and split into tokens
     * 2. Set a specific timestamp using vm.warp for predictable testing
     * 3. Perform redemption at the warped timestamp
     * 4. Verify the redeemTimestamp matches the expected timestamp
     *
     * This validates that the timestamp recording works correctly for tracking redemptions.
     */
    function test_redeemTimestampIsUpdated() public {
        // Arrange - Set up escrow and split
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 totalSplits = 100;
        address recipient = makeAddr("recipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(totalSplits, recipient);

        // Verify redeemTimestamp is initially zero
        (,,,, uint64 redeemTimestampBefore) = splitERC721.splitNFT();
        assertEq(redeemTimestampBefore, 0, "Redeem timestamp should be zero before redemption");

        // Set specific timestamp for predictable testing
        uint256 redeemTime = 1234567890;
        vm.warp(redeemTime);

        // Act - Redeem the NFT
        vm.prank(recipient);
        splitERC721.redeem();

        // Assert - Verify redeemTimestamp is correctly set
        (,,,, uint64 redeemTimestampAfter) = splitERC721.splitNFT();
        assertEq(redeemTimestampAfter, uint64(redeemTime), "Redeem timestamp should match the warped time");
    }

    /**
     * @dev Test to verify that the NFTRedeemed event is correctly emitted when redeeming an NFT.
     * This test ensures that external systems can properly track and respond to redemption
     * events through the emitted event data.
     *
     * The event is critical for:
     * - Off-chain indexing and monitoring systems
     * - Front-end applications tracking redemptions
     * - Analytics and reporting tools
     * - Integration with other protocols
     */
    function test_emitsNFTRedeemedEvent() public {
        // Arrange - Set up escrow and split
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);
        uint24 totalSplits = 100;
        address recipient = makeAddr("recipient");

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        vm.prank(ANOTHER_ADDRESS);
        splitERC721.split(totalSplits, recipient);

        // Act & Assert - Expect the event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit ISplitERC721.NFTRedeemed({nftContract: address(mockNFT), tokenId: TOKEN_ID, redeemer: recipient});

        vm.prank(recipient);
        splitERC721.redeem();
    }

    // --------------------------- METADATA --------------------------

    /**
     * @dev Test to verify that the uri() function correctly returns the URI of the escrowed NFT.
     * This test ensures that split tokens inherit the metadata URI from the original NFT,
     * allowing external systems to display correct information about the underlying asset.
     *
     * Test scenario:
     * 1. Set up NFT escrow (MockERC721 should return a predictable URI)
     * 2. Call uri() function on the split contract
     * 3. Verify it returns the same URI as calling tokenURI() on the original NFT
     *
     * This ensures split tokens maintain a connection to the original NFT's metadata.
     */
    function test_uriReturnsOriginalNFTUri() public {
        // Arrange - Set up escrow
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        // Get the expected URI from the original NFT
        string memory expectedURI = mockNFT.tokenURI(TOKEN_ID);

        // Act - Call uri() on the split contract
        string memory actualURI = splitERC721.uri(0); // Token ID 0 represents the split tokens

        // Assert - Verify URIs match
        assertEq(actualURI, expectedURI, "Split contract URI should match original NFT URI");

        // Additional verification - ensure the URI is not empty (assuming MockERC721 returns valid URI)
        assertTrue(bytes(actualURI).length > 0, "URI should not be empty");
    }

    /**
     * @dev Test to verify that uri() returns the same URI regardless of the tokenId parameter.
     * The function always returns the escrowed NFT's URI, ignoring the input tokenId.
     */
    function test_uriIgnoresTokenIdParameter() public {
        // Arrange
        vm.prank(NFT_OWNER);
        mockNFT.setApprovalForAll(ANOTHER_ADDRESS, true);

        vm.prank(ANOTHER_ADDRESS);
        mockNFT.safeTransferFrom(NFT_OWNER, address(splitERC721), TOKEN_ID);

        string memory expectedURI = mockNFT.tokenURI(TOKEN_ID);

        // Act & Assert - Different tokenId inputs should return same URI
        assertEq(splitERC721.uri(0), expectedURI, "URI should be same for tokenId 0");
        assertEq(splitERC721.uri(1), expectedURI, "URI should be same for tokenId 1");
        assertEq(splitERC721.uri(999), expectedURI, "URI should be same for tokenId 999");
    }
}
