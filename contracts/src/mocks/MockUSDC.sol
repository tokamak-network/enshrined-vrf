// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @title MockUSDC
/// @notice Minimal 6-decimal ERC20 for local/devnet testing of PongyBet.
///         Anyone can `faucet()` themselves $100 once per 15 minutes.
contract MockUSDC {
    string public constant name = "Mock USD Coin";
    string public constant symbol = "USDC";
    uint8  public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public lastFaucetAt;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        unchecked { balanceOf[from] -= amount; }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    /// @notice Self-serve faucet: $100 USDC, rate-limited to once per 15 min.
    function faucet() external {
        require(block.timestamp - lastFaucetAt[msg.sender] >= 15 minutes, "cooldown");
        lastFaucetAt[msg.sender] = block.timestamp;
        uint256 amount = 100 * 10**decimals;
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        emit Transfer(address(0), msg.sender, amount);
    }

    /// @notice Dev helper: mint arbitrary USDC to an address. Not rate-limited.
    ///         Keep this contract out of production; it has no owner gate.
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
