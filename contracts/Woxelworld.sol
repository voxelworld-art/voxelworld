// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Optional on-chain check for an agent identity. Set by the owner once the
/// real Agent ID registry address is known. While unset, the check is skipped.
interface IAgentRegistry {
    function hasAgentId(address account) external view returns (bool);
}

/// @title Woxelworld — 4,444 voxel works on BNB Chain
/// @notice Free mint, one per wallet, plus a tiered creator fee forwarded to the owner:
///         exactly 0.0001 BNB for mints 1–400, exactly 0.0003 BNB for mints 401–4,444.
contract Woxelworld is ERC721, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 4444;
    uint256 public constant EARLY_LIMIT = 400;
    uint256 public constant FEE_EARLY = 0.0001 ether;
    uint256 public constant FEE_LATE = 0.0003 ether;

    uint256 public totalSupply;
    bool public mintOpen = true;
    address public agentRegistry; // zero = agent check disabled
    string private _baseTokenURI;

    mapping(uint256 => bytes32) public seedOf;

    event Minted(address indexed to, uint256 indexed tokenId, bytes32 seed);

    error MintClosed();
    error SoldOut();
    error OnlyEOA();
    error NoAgentId();
    error AlreadyMinted();
    error WrongFee(uint256 expected);
    error FeeTransferFailed();

    constructor() ERC721("Woxelworld", "WOXEL") Ownable(msg.sender) {}

    function currentFee() public view returns (uint256) {
        return totalSupply < EARLY_LIMIT ? FEE_EARLY : FEE_LATE;
    }

    function mint() external payable {
        if (!mintOpen) revert MintClosed();
        if (totalSupply >= MAX_SUPPLY) revert SoldOut();
        if (msg.sender != tx.origin) revert OnlyEOA();
        if (agentRegistry != address(0) && !IAgentRegistry(agentRegistry).hasAgentId(msg.sender)) revert NoAgentId();
        if (balanceOf(msg.sender) != 0) revert AlreadyMinted();
        uint256 fee = currentFee();
        if (msg.value != fee) revert WrongFee(fee);

        uint256 tokenId = ++totalSupply;
        bytes32 seed = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, tokenId));
        seedOf[tokenId] = seed;
        _safeMint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, seed);

        (bool ok, ) = payable(owner()).call{value: msg.value}("");
        if (!ok) revert FeeTransferFailed();
    }

    // ---------- owner ----------
    function setMintOpen(bool open) external onlyOwner { mintOpen = open; }
    function setAgentRegistry(address registry) external onlyOwner { agentRegistry = registry; }
    function setBaseURI(string calldata uri) external onlyOwner { _baseTokenURI = uri; }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return bytes(_baseTokenURI).length == 0 ? "" : string.concat(_baseTokenURI, tokenId.toString());
    }
}
