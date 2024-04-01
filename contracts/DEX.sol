// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error DEX__AlreadyHasLiquidity();
error DEX__FailToTransfer(address sender, uint256 tokens);
error DEX__NoEthSent(uint256 amount);
error DEX__NoEnoughEth(uint256 reservedEth, uint256 ethAmount);
error DEX__NoEnoughTokens(uint256 reservedToken, uint256 tokenAmount);
error DEX__NoTokenSent(uint256 tokenAmount);
error DEX__RevertedSwap();

contract DEX {
	/* ========== GLOBAL VARIABLES ========== */

	IERC20 token; //instantiates the imported contract

	/* ========== EVENTS ========== */

	event EthToTokenSwap(
		address swapper,
		uint256 tokenOutput,
		uint256 ethInput
	);

	event TokenToEthSwap(
		address swapper,
		uint256 tokensInput,
		uint256 ethOutput
	);

	event LiquidityProvided(
		address liquidityProvider,
		uint256 liquidityMinted,
		uint256 ethInput,
		uint256 tokensInput
	);

	event LiquidityRemoved(
		address liquidityRemover,
		uint256 liquidityWithdrawn,
		uint256 tokensOutput,
		uint256 ethOutput
	);

	uint256 public totalLiquidity;
	mapping(address => uint256) public liquidity;

	/* ========== CONSTRUCTOR ========== */

	constructor(address token_addr) {
		token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	function init(uint256 tokens) public payable returns (uint256) {
		if (totalLiquidity > 0) {
			revert DEX__AlreadyHasLiquidity();
		}
		totalLiquidity = address(this).balance;
		liquidity[msg.sender] = totalLiquidity;
		bool success = token.transferFrom(msg.sender, address(this), tokens);
		if (!success) {
			revert DEX__FailToTransfer(msg.sender, tokens);
		}
		return totalLiquidity;
	}

	function price(
		uint256 xInput,
		uint256 xReserves,
		uint256 yReserves
	) public pure returns (uint256 yOutput) {
		uint256 xInputWithFee = xInput * 997;
		uint256 numerator = xInputWithFee * yReserves;
		uint256 denominator = (xReserves * 1000) + xInputWithFee;
		return (numerator / denominator);
	}

	function getLiquidity(address lp) public view returns (uint256) {
		return liquidity[lp];
	}

	function ethToToken() public payable returns (uint256 tokenOutput) {
		if (msg.value <= 0) {
			revert DEX__NoEthSent(msg.value);
		}
		uint256 reservedEth = address(this).balance - msg.value;
		uint256 reservedTokens = token.balanceOf(address(this));
		tokenOutput = price(msg.value, reservedEth, reservedTokens);
		if (reservedTokens < tokenOutput) {
			revert DEX__NoEnoughTokens(reservedTokens, tokenOutput);
		}
		bool success = token.transfer(msg.sender, tokenOutput);
		if (!success) {
			revert DEX__FailToTransfer(address(this), tokenOutput);
		}
		emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);

		return tokenOutput;
	}

	function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
		if (tokenInput <= 0) {
			revert DEX__NoTokenSent(tokenInput);
		}
		uint256 reservedToken = token.balanceOf(address(this));
		uint256 reservedEth = address(this).balance;
		ethOutput = price(tokenInput, reservedToken, reservedEth);
		if (reservedEth < ethOutput) {
			revert DEX__NoEnoughEth(reservedEth, ethOutput);
		}
		bool tokenTransfer = token.transferFrom(
			msg.sender,
			address(this),
			tokenInput
		);
		if (!tokenTransfer) {
			revert DEX__RevertedSwap();
		}
		(bool success, ) = address(msg.sender).call{ value: ethOutput }("");
		if (!success || !tokenTransfer) {
			revert DEX__FailToTransfer(address(this), ethOutput);
		}
		emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);

		return ethOutput;
	}

	function deposit() public payable returns (uint256 tokensDeposited) {
		require(msg.value > 0, "Must send value when depositing");
		uint256 ethReserve = address(this).balance - msg.value;
		uint256 tokenReserve = token.balanceOf(address(this));
		uint256 tokenDeposit;

		tokenDeposit = ((msg.value * tokenReserve) / ethReserve) + 1;

		uint256 liquidityMinted = (msg.value * totalLiquidity) / ethReserve;
		liquidity[msg.sender] += liquidityMinted;
		totalLiquidity += liquidityMinted;

		require(token.transferFrom(msg.sender, address(this), tokenDeposit));
		emit LiquidityProvided(
			msg.sender,
			liquidityMinted,
			msg.value,
			tokenDeposit
		);
		return tokenDeposit;
	}

	function withdraw(
		uint256 amount
	) public returns (uint256 eth_amount, uint256 token_amount) {
		require(
			liquidity[msg.sender] >= amount,
			"withdraw: sender does not have enough liquidity to withdraw."
		);
		uint256 ethReserve = address(this).balance;
		uint256 tokenReserve = token.balanceOf(address(this));
		uint256 ethWithdrawn;

		ethWithdrawn = (amount * ethReserve) / totalLiquidity;

		uint256 tokenAmount = (amount * tokenReserve) / totalLiquidity;
		liquidity[msg.sender] -= amount;
		totalLiquidity -= amount;
		(bool sent, ) = payable(msg.sender).call{ value: ethWithdrawn }("");
		require(sent, "withdraw(): revert in transferring eth to you!");
		require(token.transfer(msg.sender, tokenAmount));
		emit LiquidityRemoved(msg.sender, amount, tokenAmount, ethWithdrawn);
		return (ethWithdrawn, tokenAmount);
	}

	receive() external payable {}

	fallback() external payable {}
}
