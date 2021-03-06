pragma solidity 0.5.12;

import "./../interfaces/TokenConverter.sol";
import "./../interfaces/uniswap/UniswapFactory.sol";
import "./../interfaces/uniswap/UniswapExchange.sol";
import "./../utils/SafeERC20.sol";
import "./../utils/SafeExchange.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";


/// @notice proxy between ConverterRamp and Uniswap
///         accepts tokens and ether, converts these to the desired token,
///         and makes approve calls to allow the recipient to transfer those
///         tokens from the contract.
/// @author Joaquin Pablo Gonzalez (jpgonzalezra@gmail.com) & Agustin Aguilar (agusxrun@gmail.com)
contract UniswapConverter is TokenConverter, Ownable {
    using SafeMath for uint256;
    using SafeExchange for UniswapExchange;
    using SafeERC20 for IERC20;

    /// @notice address to identify operations with ETH
    IERC20 constant internal ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    /// @notice registry of ERC20 tokens that have been added to the system
    ///         and the exchange to which they are associated.
    UniswapFactory public factory;

    constructor (address _uniswapFactory) public {
        factory = UniswapFactory(_uniswapFactory);
    }

    function convertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount,
        uint256 _minReceive
    ) external payable returns (uint256 _received) {
        _pull(_fromToken, _fromAmount);

        UniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            _received = _factory.getExchange(_toToken).ethToTokenTransferInput.value(
                _fromAmount
            )(
                1,
                uint(-1),
                msg.sender
            );
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // Load Uniswap exchange
            UniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKEN to ETH
            // and send directly to msg.sender
            _approveOnlyOnce(_fromToken, address(exchange), _fromAmount);
            _received = exchange.tokenToEthTransferInput(
                _fromAmount,
                1,
                uint(-1),
                msg.sender
            );
        } else {
            // Load Uniswap exchange
            UniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKENA to ETH
            // and send it to this contract
            _approveOnlyOnce(_fromToken, address(exchange), _fromAmount);
            _received = exchange.tokenToTokenTransferInput(
                _fromAmount,
                1,
                1,
                uint(-1),
                msg.sender,
                address(_toToken)
            );
        }

        require(_received >= _minReceive, "_received is not enought");
    }

    function convertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount,
        uint256 _maxSpend
    ) external payable returns (uint256 _spent) {
        _pull(_fromToken, _maxSpend);

        UniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // Convert ETH to TOKEN
            // and send directly to msg.sender
            _spent = _factory.getExchange(_toToken).ethToTokenTransferOutput.value(
                _maxSpend
            )(
                _toAmount,
                uint(-1),
                msg.sender
            );
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // Load Uniswap exchange
            UniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKEN to ETH
            // and send directly to msg.sender
            _approveOnlyOnce(_fromToken, address(exchange), _maxSpend);
            _spent = exchange.tokenToEthTransferOutput(
                _toAmount,
                _maxSpend,
                uint(-1),
                msg.sender
            );
        } else {
            // Load Uniswap exchange
            UniswapExchange exchange = _factory.getExchange(_fromToken);
            // Convert TOKEN to ETH
            // and send directly to msg.sender
            _approveOnlyOnce(_fromToken, address(exchange), _maxSpend);
            _spent = exchange.tokenToTokenTransferOutput(
                _toAmount,
                _maxSpend,
                uint(-1),
                uint(-1),
                msg.sender,
                address(_toToken)
            );
        }

        require(_spent <= _maxSpend, "_maxSpend exceed");
        if (_spent < _maxSpend) {
            _transfer(_fromToken, msg.sender, _maxSpend - _spent);
        }
    }

    function getPriceConvertFrom(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _fromAmount
    ) external view returns (uint256 _receive) {
        UniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // ETH -> TOKEN convertion
            _receive = _factory.getExchange(_toToken).getEthToTokenInputPrice(_fromAmount);
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // TOKEN -> ETH convertion
            _receive = _factory.getExchange(_fromToken).getTokenToEthInputPrice(_fromAmount);
        } else {
            // TOKENA -> TOKENB convertion
            //   equals to: TOKENA -> ETH -> TOKENB
            uint256 ethBought = _factory.getExchange(_fromToken).getTokenToEthInputPrice(_fromAmount);
            _receive = _factory.getExchange(_toToken).getEthToTokenInputPrice(ethBought);
        }
    }

    function getPriceConvertTo(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _toAmount
    ) external view returns (uint256 _spend) {
        UniswapFactory _factory = factory;

        if (_fromToken == ETH_TOKEN_ADDRESS) {
            // ETH -> TOKEN convertion
            _spend = _factory.getExchange(_toToken).getEthToTokenOutputPrice(_toAmount);
        } else if (_toToken == ETH_TOKEN_ADDRESS) {
            // TOKEN -> ETH convertion
            _spend = _factory.getExchange(_fromToken).getTokenToEthOutputPrice(_toAmount);
        } else {
            // TOKENA -> TOKENB convertion
            //   equals to: TOKENA -> ETH -> TOKENB
            uint256 ethSpend = _factory.getExchange(_toToken).getEthToTokenOutputPrice(_toAmount);
            _spend = _factory.getExchange(_fromToken).getTokenToEthOutputPrice(ethSpend);
        }
    }

    function _pull(
        IERC20 _token,
        uint256 _amount
    ) private {
        if (_token == ETH_TOKEN_ADDRESS) {
            require(msg.value == _amount, "sent eth is not enought");
        } else {
            require(msg.value == 0, "method is not payable");
            require(_token.transferFrom(msg.sender, address(this), _amount), "error pulling tokens");
        }
    }

    function _transfer(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) private {
        if (_token == ETH_TOKEN_ADDRESS) {
            _to.transfer(_amount);
        } else {
            require(_token.transfer(_to, _amount), "error sending tokens");
        }
    }

    function _approveOnlyOnce(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) private {
        uint256 allowance = _token.allowance(address(this), _spender);
        if (allowance < _amount) {
            if (allowance != 0) {
                _token.clearApprove(_spender);
            }

            _token.approve(_spender, uint(-1));
        }
    }

    function emergencyWithdraw(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        _token.transfer(_to, _amount);
    }

    function() external payable {
        // solhint-disable-next-line
        require(tx.origin != msg.sender, "uniswap-converter: send eth rejected");
    }
}
