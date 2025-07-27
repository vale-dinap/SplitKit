// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockERC721
 * @dev Contract to deploy ERC721 tokens, used for testing purposes.
 */
contract MockERC721 is ERC721 {
    // Base URI for the token metadata
    string public BASE_URI;

    /**
     * @dev Constructor to initialize the ERC721 token with a name, symbol, and base URI.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param _baseURI The base URI for the token metadata.
     */
    constructor(string memory name, string memory symbol, string memory _baseURI) ERC721(name, symbol) {
        BASE_URI = _baseURI;
    }

    /**
     * @dev Ovverride function to return the "BASE_URI" variable as base URI for the token metadata.
     * @return The base URI as a string.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return BASE_URI;
    }

    /**
     * @dev Function to mint a new token to a specified address.
     * @param to The address to which the token will be minted.
     * @param tokenId The ID of the token to be minted.
     */
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
