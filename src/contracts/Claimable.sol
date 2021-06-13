// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface ERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

/**
 * @title Claimable Protocol
 * @dev Smart contract allow recipients to claim ERC20 tokens
 *      according to an initial cliff and a vesting period
 *      Formual:
 *      - claimable at cliff: (cliff / vesting) * amount
 *      - claimable at time t after cliff (t0 = start time)
 *        (t - t0) / vesting * amount
 *      - multiple claims, last claim at t1, claim at t:
 *        (t - t1) / vesting * amount
 */
contract Claimable is Context {
    using SafeMath for uint256;

    /// @notice unique claim ticket id, auto-increment
    uint256 public currentId;

    /// @notice claim ticket
    /// @dev payable is not needed for ERC20, need more work to support Ether
    struct Ticket {
      address token; // ERC20 token address
      address payable grantor; // grantor address
      address payable beneficiary;
      uint256 cliff; // cliff time from creation in days
      uint256 vesting; // vesting period in days
      uint256 amount; // initial funding amount
      uint256 claimed; // amount already claimed
      uint256 balance; // current balance
      uint256 createdAt; // begin time
      uint256 lastClaimedAt;
      uint256 numClaims;
      bool irrevocable; // cannot be revoked
      bool isRevoked; // return balance to grantor
      uint256 revokedAt; // revoke timestamp
    //   mapping (uint256
    //     => mapping (uint256 => uint256)) claims; // claimId => lastClaimAt => amount
    }

    /// @notice address => id[]
    /// @dev this is expensive but make it easy to create management UI
    mapping (address => uint256[]) public grantorTickets;
    mapping (address => uint256[]) public beneficiaryTickets;

    /**
     * Claim tickets
     */
    /// @notice id => Ticket
    mapping (uint256 => Ticket) public tickets;

    event TicketCreated(uint256 id, address token, uint256 amount, bool irrevocable);
    event Claimed(uint256 id, address token, uint256 amount);
    event Revoked(uint256 id, uint256 amount);

    /// @notice special cases: cliff = period: all claimable after the cliff
    function create(address _token, address payable _beneficiary, uint256 _cliff, uint256 _vesting, uint256 _amount, bool _irrevocable) public returns (uint256 ticketId) {
      /// @dev sender needs to approve this contract to fund the claim
      require(_recipient != address(0), "Beneficiary is required");
      require(_amount > 0, "Amount is required");
      require(_vesting >= _cliff, "Vesting period should be equal or longer to the cliff");
      ERC20 token = ERC20(_token);
      require(token.transfer(address(this), _amount), "Funding failed.");
      ticketId = currentId++;
      Ticket storage ticket = tickets[ticketId];
      ticket.token = _token;
      ticket.grantor = _msgSender();
      ticket.beneficiary = _beneficiary;
      ticket.cliff = _cliff;
      ticket.vesting = _vesting;
      ticket.amount = _amount;
      ticket.balance = _amount;
      ticket.createdAt = block.timestamp;
      ticket.irrevocable = _irrevocable;
      grantorTickets[_msgSender()].push(ticketId);
      beneficiaryTickets[_msgSender()].push(ticketId);
      emit TicketCreated(ticketId, _token, _amount, _irrevocable);
    }

    /// @notice check available claims, only grantor or beneficiary can call
    function check(uint256 _id) public returns (uint256 amount) {
        Ticket memory ticket = tickets[_id];
        require(ticket.grantor == _msgSender() || ticket.beneficiary == _msgSender(), "Only grantor or beneficiary can check available claim.");
        require(ticket.isRevoked == false, "Ticket is already revoked");
        require(ticket.balance > 0, "Ticket has no balance.");
        amount = _available(_id);
    }

    /// @notice claim available balance, only beneficiary can call
    function claim(uint256 _id) public returns (uint256 success) {
      Ticket storage ticket = tickets[_id];
      require(ticket.beneficiary == _msgSender(), "Only beneficiary can claim.");
      require(ticket.isRevoked == false, "Ticket is already revoked");
      require(ticket.balance > 0, "Ticket has no balance.");
      ERC20 token = ERC20(ticket.token);
      uint256 amount = _available(_id);
      require(token.transferFrom(address(this), _msgSender(), amount), "Claim failed");
      ticket.claimed = SafeMath.add(ticket.claimed, amount);
      ticket.balance = SafeMath.sub(ticket.balance, amount);
      ticket.lastClaimedAt = block.timestamp;
      ticket.numClaims = SafeMath.add(ticket.numClaims, 1);
      emit Claimed(_id, ticket.token, amount);
      success = true;
    }

    /// @notice revoke ticket, balance returns to grantor, only grantor can call
    function revoke(uint256 _id) public returns (bool success) {
      Ticket storage ticket = tickets[_id];
      require(ticket.grantor == _msgSender(), "Only grantor can revoke.");
      require(ticket.irrevocable == false, "Ticket is irrevocable.");
      require(ticket.isRevoked == false, "Ticket is already revoked");
      require(ticket.balance > 0, "Ticket has no balance.");
      ERC20 token = ERC20(ticket.token);
      require(token.transferFrom(address(this), _msgSender(), ticket.balance), "Return balance failed");
      ticket.isRevoked = true;
      ticket.balance = 0;
      emit Revoked(_id, ticket.balance);
    }

    /// @dev checks the ticket has cliffed or not
    function _hasCliffed(uint256 _id) internal returns (bool) {
        Ticket memory ticket = tickets[_id];
        return block.timestamp > SafeMath.add(ticket.createdAt, ticket.cliff * 1 days);
    }

    /// @dev calculates the available balances excluding cliff and claims
    function _unlocked(uint256 _id) internal returns (uint256 amount) {
        Ticket memory ticket = tickets[_id];
        uint256 timeLapsed = SafeMath.sub(block.timestamp - ticket.createdAt); // in seconds
        uint256 daysLapsed = SafeMath.div(timeLapsed, 86400); // demonimator: 60 x 60 x 24
        amount = SafeMath.mul(
            SafeMath.div(daysLapsed, ticket.vesting),
            ticket.amount
        );
    }

    /// @dev calculates available for claim
    function _available(uint256 _id) internal returns (uint256 amount) {
        Ticket memory ticket = tickets[_id];
        if (_hasCliffed(_id)) {
            amount = SafeMath.sub(_unlocked(_id), ticket.claimed);
        } else {
            amount = 0;
        }
    }

    /**
     * Entries
     */
    // /// @notice Entries: poolId => sender => bucketId => amount
    // mapping (uint256 => mapping (address => mapping (uint256 => uint256))) public entry;
    // /// @notice Bucket size: poolId => bucketId => amount (total)
    // mapping (uint256 => mapping (uint256 => uint256)) public bucketSize;
    // /// @notice Bucket size: poolId => bucketId => address => amount (total)
    // mapping (uint256 => mapping (uint256 => mapping (address => uint256))) public bucketSizePerAddress;
    // /// @notice Pool size: poolId => amount (total)
    // mapping (uint256 => uint256) public poolSize;
    // /// @notice address in each bucket: poolId => bucketId => dynamic address array
    // /// @dev this is expensive but needed to settle on-chain
    // mapping (uint256 => mapping (uint256 => address[])) public bucketAddresses;

    // /**
    //  * Pools
    //  */
    // /// @notice Is pool live? poolId => boolean
    // mapping (uint256 => bool) public live;
    // /// @notice Is pool settled? poolId => boolean
    // mapping (uint256 => bool) public settled;
    // /// @notice Pool metadata 1
    // mapping (uint256 => string) public metadata1;
    // /// @notice Pool metadata 2
    // mapping (uint256 => string) public metadata2;
    // /// @notice Pool metadata 3
    // mapping (uint256 => string) public metadata3;
    // /// @notice Pool metadata 4
    // mapping (uint256 => string) public metadata4;

    /// @notice event for entry logged
    // event EntryCreated(uint256 poolId, address sender, uint256 bucketId, uint256 amount);
    // /// @notice poolId with winning bucketId with the total poolSize
    // event Settled(uint256 poolId, uint256 bucketId, uint256 poolSize);
    // /// @dev Metadata set
    // event MetadataSet(string handle, string data);
    // /// @dev Fee updated
    // event FeePercentUpdated(uint256 feePercent);
    // /// @dev Pool lolockPool
    // event PoolLocked(uint256 poolId);
    // /// @dev Pool created
    // event PoolCreated(uint256 poolId);
    // /// @dev DEBUG
    // event DEBUG(string message, uint256 amount);

    // modifier isAdmin() {
    //     require(
    //         _msgSender() == admin,
    //         "Sender not authorized."
    //     );
    //     _;
    // }

    // constructor() {
    //     /// @dev set creator as admin
    //     admin = _msgSender();
    //     /// @dev auto initiate first pool
    //     // live[currentPoolId] = true;
    //     // emit PoolCreated(currentPoolId);
    // }

    // fallback() external payable {}

    // function createPool() isAdmin public {
    //     currentPoolId = SafeMath.add(currentPoolId, 1);
    //     live[currentPoolId] = true;
    //     emit PoolCreated(currentPoolId);
    // }

    // function lockPool(uint256 _poolId) isAdmin public {
    //     live[_poolId] = false;
    //     emit PoolLocked(_poolId);
    // }

    // function setFeePercent(uint256 _feePercent) isAdmin public {
    //     feePercent = _feePercent;
    //     emit FeePercentUpdated(_feePercent);
    // }

    // /// @dev setting metadata.
    // function setMetadata1(uint256 _poolId, string calldata _metadata) isAdmin public {
    //     metadata1[_poolId] = _metadata;
    //     emit MetadataSet("metadata1", _metadata);
    // }
    // function setMetadata2(uint256 _poolId, string calldata _metadata) isAdmin public {
    //     metadata2[_poolId] = _metadata;
    //     emit MetadataSet("metadata2", _metadata);
    // }
    // function setMetadata3(uint256 _poolId, string calldata _metadata) isAdmin public {
    //     metadata3[_poolId] = _metadata;
    //     emit MetadataSet("metadata3", _metadata);
    // }
    // function setMetadata4(uint256 _poolId, string calldata _metadata) isAdmin public {
    //     metadata4[_poolId] = _metadata;
    //     emit MetadataSet("metadata4", _metadata);
    // }

    // function settlePool(uint256 _poolId, uint256 _winningBucketId) isAdmin public {
    //     require(_winningBucketId < maxBuckets && _winningBucketId >= 0, "Invalid bucketId");
    //     /// @dev Pool winner distribution
    //     for (uint256 i=0; i < bucketAddresses[_poolId][_winningBucketId].length; i++) {
    //         token.transfer(
    //             bucketAddresses[_poolId][_winningBucketId][i],
    //             SafeMath.div(
    //                 SafeMath.mul(
    //                     bucketSizePerAddress[_poolId][_winningBucketId][bucketAddresses[_poolId][_winningBucketId][i]],
    //                     SafeMath.mul(
    //                         poolSize[_poolId],
    //                         SafeMath.sub(100, feePercent)
    //                     )
    //                 ),
    //                 SafeMath.mul(
    //                     bucketSize[_poolId][_winningBucketId],
    //                     100
    //                 )
    //             )
    //         );
    //     }
    //     /// @dev Lock pool
    //     lockPool(_poolId);
    //     /// @dev Delete all bucket addresses
    //     for (uint256 j=0; j < maxBuckets; j++) {
    //         delete bucketAddresses[_poolId][j];
    //     }
    //     emit Settled(_poolId, _winningBucketId, poolSize[_poolId]);
    // }

    // function enter(uint256 _poolId, uint256 _bucketId, uint256 _amount) public {
    //     require(live[_poolId] == true && settled[_poolId] == false, "Invalid pool id");
    //     require(_bucketId < maxBuckets && _bucketId >= 0, "Invalid bucketId");
    //     require(token.balanceOf(_msgSender()) >= _amount, "Insufficient balance");
    //     /// @dev user needs to approve the contract address explicitly
    //     require(token.transferFrom(_msgSender(), address(this), _amount), "Payment transfer failed");
    //     /// @dev add address for new users
    //     if (entry[_poolId][_msgSender()][_bucketId] == 0 && _amount > 0) {
    //         bucketAddresses[_poolId][_bucketId].push(_msgSender());
    //     }
    //     /// @dev log entry
    //     entry[_poolId][_msgSender()][_bucketId] = SafeMath.add(entry[_poolId][_msgSender()][_bucketId], _amount);
    //     /// @dev log bucketSize
    //     bucketSize[_poolId][_bucketId] = SafeMath.add(bucketSize[_poolId][_bucketId], _amount);
    //     /// @dev log bucketSize per address
    //     bucketSizePerAddress[_poolId][_bucketId][_msgSender()] = SafeMath.add(bucketSizePerAddress[_poolId][_bucketId][_msgSender()], _amount);
    //     /// @dev log poolSize
    //     poolSize[_poolId] = SafeMath.add(poolSize[_poolId], _amount);
    //     emit EntryCreated(_poolId, _msgSender(), _bucketId, _amount);
    // }
}
