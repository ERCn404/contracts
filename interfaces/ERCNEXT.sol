// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/utils/Address.sol';
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

abstract contract ERCNEXT is Context, Ownable, IERC1155MetadataURI, IERC20Metadata {
    using Address for address;

    uint constant private MULTIPLIER = 40;

    mapping(address => uint256[MULTIPLIER]) private userSlots;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    bool public tradingStarted = false;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) public eventExcluded;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
    string private _uri;
    uint FF = type(uint).max;


    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _mint(msg.sender, 10240 * (10 ** decimals()));

        address poolV2 = computeAddressV2();
        address poolV3 = computeAddressV3();
        automatedMarketMakerPairs[poolV2] = true;
        automatedMarketMakerPairs[poolV3] = true;
        eventExcluded[owner()] = true;
    }

    function startTrading() public onlyOwner {
        tradingStarted = true;
    }

    function computeAddressV3() internal view returns (address pool) {
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address token = address(this);
        address token1 = weth;
        address token0 = token;
        if (token1 < token0) {
            token0 = weth;
            token1 = token;
        }
        pool = address(
            uint160(uint(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        0x1F98431c8aD98523631AE4a59f267346ea31F984,
                        keccak256(abi.encode(token0, token1, 10000)),
                        POOL_INIT_CODE_HASH
                    )
                )
            ))
        );
    }

    function computeAddressV2() internal view returns (address pool) {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address token = address(this);
        address token1 = weth;
        address token0 = token;
        if (token1 < token0) {
            token0 = weth;
            token1 = token;
        }
        address factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

        pool = address(uint160(uint(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'
        )))));
    }


    function balanceOf(address to) public view virtual returns (uint) {
        return _balances[to];
    }

    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        require(account != address(0), "ERC1155: address zero is not a valid owner");
        (uint row, uint col) = idToBitmapAddress(id);

        return ((1 << col) & userSlots[account][row]) > 0 ? 1 : 0;
    }

    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
    public
    view
    virtual
    override
    returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }
        return batchBalances;
    }


    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }


    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return _allowances[account][operator] >= totalSupply();
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function excludeFromEvents(bool exclude) external {
        eventExcluded[msg.sender] = exclude;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        //TODO
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }


    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) internal {
        automatedMarketMakerPairs[pair] = value;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        if (!tradingStarted) {
            require(
                automatedMarketMakerPairs[to],
                "Trading is not active."
            );
        }
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        if (amount >= 1e18) {
            if (!tradingStarted && automatedMarketMakerPairs[to]) {
                fastBatchTransferNFT(from, to);
            } else {
                batchTransferNFT(from, to, amount / 1e18, eventExcluded[tx.origin] || eventExcluded[to]);
            }
        }
        emit Transfer(from, to, amount);
    }

    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        require(to != address(0), "ERC1155: transfer to the zero address");

        amount = 1;

        address operator = _msgSender();

        uint256 fromBalance = balanceOf(from, id);
        require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");
        uint256 fromBalanceERC = _balances[from];
        require(fromBalanceERC >= amount * 1e18, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalanceERC - amount * 1e18;
            _balances[to] += amount * 1e18;
        }
        transferNFT(from, to, id);

        emit TransferSingle(operator, from, to, id, amount);

        _doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }


    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 amount = 1;
            uint256 fromBalance = balanceOf(from, id);
            require(fromBalance >= amount, "ERC1155: insufficient balance for transfer");
            transferNFT(from, to, id);
        }

        uint256 fromBalanceERC = _balances[from];
        require(fromBalanceERC >= amounts.length * 1e18, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalanceERC - amounts.length * 1e18;
            _balances[to] += amounts.length * 1e18;
        }

        emit TransferBatch(operator, from, to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    function transferNFT(address from, address to, uint id) internal {
        (uint row, uint col) = idToBitmapAddress(id);
        uint256 slotFrom = userSlots[from][row];
        uint256 slotTo = userSlots[to][row];

        slotFrom = removeNFT(slotFrom, col);
        slotTo = addNFT(slotTo, col);
        userSlots[from][row] = slotFrom;
        userSlots[to][row] = slotTo;
    }


    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }

        emit Transfer(address(0), account, amount);
        _mintNFTBatchInitial(account);

    }

    function _mintNFTBatchInitial(address account) private {
        require(account != address(0), "ERC20: mint to the zero address");
        for (uint i = 0; i < MULTIPLIER; i++) {
            userSlots[account][i] = FF;
        }
    }

    function fastBatchTransferNFT(address from, address to) private {
        for (uint i = 0; i < MULTIPLIER; i++) {
            userSlots[to][i] = userSlots[from][i];
            userSlots[from][i] = 0;
        }
    }


    function batchTransferNFT(address from, address to, uint count, bool skipEvent) private returns (uint256[] memory ids, uint256[] memory amounts)  {
        ids = new uint[](count);
        amounts = new uint[](count);
        uint idx = 0;
        for (uint i = 0; i < MULTIPLIER; i++) {
            if (count == 0) {
                break;
            }
            uint free = userSlots[from][i];
            if (free > 0) {
                uint slotFrom = userSlots[from][i];
                uint slotTo = userSlots[to][i];
                uint totalAmount = popCount(free);
                bool needMoveAllNFTs = totalAmount <= count;
                if(skipEvent && needMoveAllNFTs) {
                    slotTo = slotTo | slotFrom;
                    slotFrom = 0;
                    count -= totalAmount;
                } else {
                    while (free > 0 && count > 0) {
                        unchecked {
                            uint p = ffs(free);
                            free = free & ~(1 << p);
                            slotFrom = removeNFT(slotFrom, p);
                            slotTo = addNFT(slotTo, p);
                            count--;
                            if (!skipEvent) {
                                ids[idx] = bitmapAddressToId(i, p);
                                amounts[idx] = 1;
                            }
                            idx++;
                        }
                    }
                }
                userSlots[from][i] = slotFrom;
                userSlots[to][i] = slotTo;
            }
        }
        if (!skipEvent) {
            emit TransferBatch(msg.sender, from, to, ids, amounts);
        }
    }


    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }


    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function name() external view virtual override returns (string memory) {
        return _name;
    }

    function symbol() external view virtual override returns (string memory) {
        return _symbol;
    }


    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC1155: setting approval status for self");
        if (approved) {
            _allowances[owner][operator] = type(uint256).max;
        } else {
            _allowances[owner][operator] = 0;
        }
        emit ApprovalForAll(owner, operator, approved);
    }


    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            if (!isApprovedForAll(owner, spender)) {
                unchecked {
                    _approve(owner, spender, currentAllowance - amount);
                }
            }
        }
    }


    function removeNFT(uint row, uint id) internal pure returns (uint) {
        return row & ~(1 << id);
    }

    function addNFT(uint row, uint id) internal pure returns (uint) {
        return row | (1 << id);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }


    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non-ERC1155Receiver implementer");
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non-ERC1155Receiver implementer");
            }
        }
    }

    function _asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    function ffs(uint256 x) internal pure returns (uint256 r) {
        assembly {
            let b := and(x, add(not(x), 1))
            r := or(shl(8, iszero(x)), shl(7, lt(0xffffffffffffffffffffffffffffffff, b)))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, b))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, b))))
            r := or(r, byte(and(div(0xd76453e0, shr(r, b)), 0x1f),
                0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
        }
    }
    function popCount(uint256 x) internal pure returns (uint256 c) {
        assembly {
            let max := not(0)
            let isMax := eq(x, max)
            x := sub(x, and(shr(1, x), div(max, 3)))
            x := add(and(x, div(max, 5)), and(shr(2, x), div(max, 5)))
            x := and(add(x, shr(4, x)), div(max, 17))
            c := or(shl(8, isMax), shr(248, mul(x, div(max, 255))))
        }
    }

    function idToBitmapAddress(uint id) internal view returns (uint row, uint col) {
        require(id <= totalSupply());
        col = id % 256;
        row = id / 256;
    }

    function bitmapAddressToId(uint row, uint col) internal pure returns (uint id) {
        id = row * 256 + col;
    }

}