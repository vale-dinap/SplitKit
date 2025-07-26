// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 *   ░██████              ░██ ░██   ░██    ░██     ░██ ░██   ░██
 *  ░██   ░██             ░██       ░██    ░██    ░██        ░██
 * ░██         ░████████  ░██ ░██░████████ ░██   ░██   ░██░████████
 *  ░████████  ░██    ░██ ░██ ░██   ░██    ░███████    ░██   ░██
 *         ░██ ░██    ░██ ░██ ░██   ░██    ░██   ░██   ░██   ░██
 *  ░██   ░██  ░███   ░██ ░██ ░██   ░██    ░██    ░██  ░██   ░██
 *   ░██████   ░██░█████  ░██ ░██    ░████ ░██     ░██ ░██    ░████
 *             ░██
 *             ░██
 */
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ISplitERC721} from "./ISplitERC721.sol";
import {ISplitERC721Errors} from "./ISplitERC721Errors.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Split ERC-721
 * @author Valerio Di Napoli
 * @notice This contract allows the fractionalization of an ERC721 NFT into multiple ERC1155 splits.
 * Using 1155 allows for an easier and more gas-efficient management of multiple splits.
 * @dev It implements the IERC721Receiver interface to handle the receipt of the NFT.
 * The contract:
 *  - allows the deployer to mint splits for an escrowed NFT and any address holding all the splits
 *    to burn them to redeem the NFT;
 *  - uses the Minimal Proxy pattern to reduce deployment costs and ensure that for each NFT being
 *    fractionalized, a new instance of the contract is created, allowing for unique state management
 *    per NFT.
 */
contract SplitERC721 is ERC1155, IERC721Receiver, ISplitERC721, ISplitERC721Errors {
    using {Strings.toString} for uint256;
    using {Strings.toString} for uint24;
    using {Strings.toChecksumHexString} for address;

    // --------------------------- STRUCTS ---------------------------

    /**
     * @notice Struct to hold the data of the fractionalized NFT.
     * @dev The struct is packed to minimize storage costs:
     * - totalSplits is a uint24, enough for 1 million splits;
     * - timestamps are stored as uint64, enough for 500+ years (until Jul 21 2554).
     * @param tokenContract Address of the NFT contract.
     * @param tokenId ID of the NFT being fractionalized.
     * @param totalSplits Total number of splits created for the NFT.
     * @param escrowTimestamp Timestamp when the NFT was escrowed - zero if not escrowed.
     * @param redeemTimestamp Timestamp when the NFT was redeemed - zero if not redeemed.
     */
    struct SplitNFT {
        // Slot 0
        address tokenContract;
        // Slot 1
        uint256 tokenId;
        // Slot 2
        uint24 totalSplits;
        uint64 escrowTimestamp;
        uint64 redeemTimestamp;
    }

    // -------------------------- CONSTANTS --------------------------

    /// @inheritdoc ISplitERC721
    uint24 public constant MIN_SPLITS = 2;

    /// @inheritdoc ISplitERC721
    uint24 public constant MAX_SPLITS = 1e6;

    // ----------------------- STATE VARIABLES -----------------------

    // Storage slot: 0
    address public escrower; // Address that escrowed the NFT, ensuring that only the escrower can mint splits
    // Storage slots: 1, 2, 3
    SplitNFT public splitNFT;

    // ------------------------- CONSTRUCTOR -------------------------

    /**
     * @dev Constructor irrelevant with MinimalProxy pattern, but required by ERC1155
     */
    constructor() ERC1155("") {}

    // -------------------------- FUNCTIONS --------------------------

    /**
     * @notice Returns the URI for the NFT's metadata by retrieving the token URI of the escrowed
     * NFT.
     * @dev The function uses a try-catch block to handle the case where the NFT contract does not
     * implement the tokenURI function, preventing a revert in such cases.
     * @param tokenId The ID of the NFT for which to retrieve the URI.
     * @return string The URI of the NFT's metadata, or an empty string if not available.
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        SplitNFT memory nft = splitNFT;
        try IERC721Metadata(nft.tokenContract).tokenURI(nft.tokenId) returns (string memory tokenURI) {
            return tokenURI;
        } catch {
            return "";
        }
    }

    /**
     * @inheritdoc ISplitERC721
     */
    function contractURI() public view returns (string memory) {
        // Split-specific collection metadata
        SplitNFT memory nft = splitNFT;
        bool redeemed = nft.redeemTimestamp != 0;
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "',
                            redeemed ? "[REDEEMED] " : "",
                            "Split of NFT #",
                            nft.tokenId.toString(),
                            '",',
                            '"description": "Token ID ',
                            nft.tokenId.toString(),
                            ", from the collection at address ",
                            nft.tokenContract.toChecksumHexString(),
                            ", fractionalized into ",
                            nft.totalSplits.toString(),
                            " splits. The original token",
                            redeemed
                                ? " has been redeemed and all splits have been burnt."
                                : " is safely stored in a smart contract and can be redeemed by burning 100% of the splits.",
                            '",',
                            '"image": "[URL]/split-logo.png"', // Example image URL, can be replaced with a state variable or function call
                            "}"
                        )
                    )
                )
            )
        );
    }

    /**
     * @notice Handles the receipt of an NFT by this contract. See IERC721Receiver for details.
     * @dev This function is called when an NFT is transferred to this contract.
     * It sets up the SplitNFT struct with the escrowed NFT data and ensures that the contract
     * can only escrow a single NFT.
     * @param operator The address that is transferring the NFT.
     * @param from The address from which the NFT is being transferred.
     * @param tokenId The ID of the NFT being transferred.
     * @param data Additional data with no specified format, sent in the call to this contract.
     * @return bytes4 The selector of this function, indicating successful receipt of the NFT.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        // The contract can only escrow a single NFT
        if (splitNFT.escrowTimestamp != 0) revert SplitERC721Error(ErrorCode.AlreadyEscrowed);
        SplitNFT memory newSplitNFT = SplitNFT({
            tokenContract: msg.sender,
            tokenId: tokenId,
            totalSplits: 0, // Will be set in the split function
            escrowTimestamp: uint64(block.timestamp),
            redeemTimestamp: 0 // Will be set when the NFT is redeemed
        });
        splitNFT = newSplitNFT;
        escrower = operator;
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @inheritdoc ISplitERC721
     */
    function split(uint24 splits, address recipient) external {
        // Ensure the caller is the same address that escrowed the NFT
        if (msg.sender != escrower) revert SplitERC721Error(ErrorCode.OnlyEscrower);
        // Ensure the recipient is not the zero address
        if (recipient == address(0)) revert SplitERC721Error(ErrorCode.InvalidRecipient);
        // Validate the number of splits
        if (splits < MIN_SPLITS || splits > MAX_SPLITS) revert InvalidNumberOfSplits(splits);
        // Read the splitNFT data from storage
        SplitNFT memory NFTData = splitNFT;
        // Ensure the NFT has not already been split
        if (NFTData.totalSplits != 0) revert SplitERC721Error(ErrorCode.AlreadySplit);
        // Ensure the NFT contract is a valid ERC721 contract
        require(
            IERC721(NFTData.tokenContract).supportsInterface(type(IERC721).interfaceId),
            SplitERC721Error(ErrorCode.InvalidNFTContract)
        );
        // Ensure that the NFT was transferred to this contract
        if (IERC721(NFTData.tokenContract).ownerOf(NFTData.tokenId) != address(this)) {
            revert NotEscrowed(NFTData.tokenContract, NFTData.tokenId);
        }
        // Mint the splits for the NFT
        splitNFT.totalSplits = splits;
        _mint(recipient, 0, splits, "");
        emit NFTFractionalized({nftContract: NFTData.tokenContract, tokenId: NFTData.tokenId, splits: splits});
    }

    /**
     * @inheritdoc ISplitERC721
     */
    function redeem() external {
        SplitNFT memory NFTData = splitNFT; // Read the splitNFT data from storage
        // Ensure the NFT is escrowed and not already redeemed
        if (NFTData.escrowTimestamp == 0) revert NotEscrowed(NFTData.tokenContract, NFTData.tokenId);
        if (NFTData.redeemTimestamp != 0) revert SplitERC721Error(ErrorCode.AlreadyRedeemed);
        uint256 balance = balanceOf(msg.sender, 0);
        if (balance != NFTData.totalSplits) revert NotEnoughSplits(balance, NFTData.totalSplits);
        splitNFT.redeemTimestamp = uint64(block.timestamp);
        // Burn all the splits to redeem the NFT
        _burn(msg.sender, 0, NFTData.totalSplits);
        IERC721(NFTData.tokenContract).safeTransferFrom(address(this), msg.sender, NFTData.tokenId);
        emit NFTRedeemed({nftContract: NFTData.tokenContract, tokenId: NFTData.tokenId, redeemer: msg.sender});
    }

    /**
     * @inheritdoc ISplitERC721
     */
    function ownershipFromSplits(uint24 splits) external view returns (uint256) {
        return (uint256(splits) * 10000) / splitNFT.totalSplits;
    }
}
