// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
  ░██████              ░██ ░██   ░██    ░██     ░██ ░██   ░██    
 ░██   ░██             ░██       ░██    ░██    ░██        ░██    
░██         ░████████  ░██ ░██░████████ ░██   ░██   ░██░████████ 
 ░████████  ░██    ░██ ░██ ░██   ░██    ░███████    ░██   ░██    
        ░██ ░██    ░██ ░██ ░██   ░██    ░██   ░██   ░██   ░██    
 ░██   ░██  ░███   ░██ ░██ ░██   ░██    ░██    ░██  ░██   ░██    
  ░██████   ░██░█████  ░██ ░██    ░████ ░██     ░██ ░██    ░████ 
            ░██                                                  
            ░██
*/

import { Clones }       from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC721 }      from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SplitERC721 }  from "./SplitERC721.sol";

/**
 * @title SplitNFT Factory
 * @author Valerio Di Napoli
 * @notice This contract manages the creation of fractionalized ERC721 tokens.
 * It allows users to split an ERC721 token into multiple fractionalized tokens (splits).
 * Each split is represented by a new instance of the SplitERC721 contract.
 * The original ERC721 token is held in escrow within the SplitERC721 contract.
 * @dev The SplitManager uses the Clones library to create minimal proxy contracts for each
 * fractionalized token, which reduces gas costs and deployment complexity.
 * The implementation of this contract is minimal and contains only the logic to create
 * the fractionalized tokens, while the actual logic for splitting and managing the splits,
 * as well as the safety checks and validations, are handled in the SplitERC721 contract.
 * This contract has no access control and no upgradeability by design, as it is meant to be
 * immutable and fully decentralized.
 */
contract SplitNFTFactory {
    using Clones for address;

    /// @notice The address of the SplitERC721 implementation contract.
    /// @dev This is the contract that will be cloned for each new split.
    address public immutable SPLIT_NFT_IMPLEMENTATION;

    /// @notice Mapping to store the addresses of all split NFT contracts created.
    mapping(uint256 contractIndex => address splitNFTContract) public splitNFTs;
    /// @dev The index is the count of split contracts created so far, starting from 0.
    uint256 public splitNFTContractsCount;

    /**
     * @notice Constructor that initializes the SplitManager with the address of the SplitERC721 implementation.
     * @dev The implementation contract is deployed once and reused for creating new splits.
     */
    constructor() {
        SPLIT_NFT_IMPLEMENTATION = new SplitERC721();
    }

    /**
     * @notice Fractionalizes an ERC721 token into multiple splits.
     * Note: Caller must be the owner of the NFT and have allowed the SplitManager contract to transfer it.
     * @dev This function allows the owner of an ERC721 token to create a fractionalized version of it.
     * It creates a new instance of the SplitERC721 contract, transfers the ERC721 token to it and
     * mints the splits. The original token remains escrowed in the SplitERC721 contract and can be
     * redeemed by burning all splits.
     * @dev Most validations are handled by the SplitERC721 contract itself:
     * - The `onERC721Received` function ensures that the contract is a valid ERC721.
     * - The `split` function validates the number of splits and the recipient.
     * - The `safeTransferFrom` function ensures that the caller is the owner of the token and has
     *   approved the SplitManager to transfer it.
     * @param tokenContract The address of the ERC721 token contract to be fractionalized.
     * @param tokenId The ID of the token to be fractionalized.
     * @param numSplits The total number of splits to create. Min/max enforced by the SplitERC721 contract.
     * @return splitAddress The address of the newly created SplitERC721 contract.
     */
    function splitNFT(
        address tokenContract,
        uint256 tokenId,
        uint24 numSplits
    ) external returns (address splitAddress) {
        splitAddress = SPLIT_NFT_IMPLEMENTATION.clone();
        splitNFTs[splitNFTContractsCount++] = splitAddress;
        IERC721(tokenContract).safeTransferFrom(msg.sender, splitAddress, tokenId);
        SplitERC721(splitAddress).split({
            splits: numSplits,
            recipient: msg.sender
        });
    }
}