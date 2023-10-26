module cetus_clmm::clmm_router {
    use std::signer;
    use std::string::String;
    use aptos_framework::coin;
    use integer_mate::i64;
    use cetus_clmm::config;
    use cetus_clmm::pool;
    use cetus_clmm::factory;
    use cetus_clmm::partner;
    use cetus_clmm::fee_tier;

    const EAMOUNT_IN_ABOVE_MAX_LIMIT: u64 = 1;
    const EAMOUNT_OUT_BELOW_MIN_LIMIT: u64 = 2;
    const EIS_NOT_VALID_TICK: u64 = 3;
    const EINVALID_LIQUIDITY: u64 = 4;
    const EPOOL_ADDRESS_ERROR: u64 = 5;
    const EINVALID_POOL_PAIR: u64 = 6;
    const ESWAP_AMOUNT_INCORRECT: u64 = 7;
    const EPOSITION_INDEX_ERROR: u64 = 8;
    const EPOSITION_IS_NOT_ZERO: u64 = 9;

    #[cmd]
    /// Transfer the `protocol_authority` to new authority.
    /// Params
    ///     - next_protocol_authority
    /// Returns
    public entry fun transfer_protocol_authority(
        protocol_authority: &signer,
        next_protocol_authority: address
    ) {
        config::transfer_protocol_authority(protocol_authority, next_protocol_authority);
    }

    #[cmd]
    /// Accept the `protocol_authority`.
    /// Params
    /// Returns
    public entry fun accept_protocol_authority(
        next_protocol_authority: &signer
    ) {
        config::accept_protocol_authority(next_protocol_authority);
    }

    #[cmd]
    /// Update the `protocol_fee_claim_authority`.
    /// Params
    ///     - next_protocol_fee_claim_authority
    /// Returns
    public entry fun update_protocol_fee_claim_authority(
        protocol_authority: &signer,
        next_protocol_fee_claim_authority: address,
    ) {
        config::update_protocol_fee_claim_authority(protocol_authority, next_protocol_fee_claim_authority);
    }

    #[cmd]
    /// Update the `pool_create_authority`.
    /// Params
    ///     - pool_create_authority
    /// Returns
    public entry fun update_pool_create_authority(
        protocol_authority: &signer,
        pool_create_authority: address
    ) {
        config::update_pool_create_authority(protocol_authority, pool_create_authority);
    }

    #[cmd]
    /// Update the `protocol_fee_rate`, the protocol_fee_rate is unique and global for the clmmpool protocol.
    /// Params
    ///     - protocol_fee_rate
    /// Returns
    public entry fun update_protocol_fee_rate(
        protocol_authority: &signer,
        protocol_fee_rate: u64
    ) {
        config::update_protocol_fee_rate(protocol_authority, protocol_fee_rate);
    }

    #[cmd]
    /// Add a new `fee_tier`. fee_tier is identified by the tick_spacing.
    /// Params
    ///     - tick_spacing
    ///     - fee_rate
    /// Returns
    public entry fun add_fee_tier(
        protocol_authority: &signer,
        tick_spacing: u64,
        fee_rate: u64
    ) {
        fee_tier::add_fee_tier(protocol_authority, tick_spacing, fee_rate);
    }

    #[cmd]
    /// Update the fee_rate of a fee_tier.
    /// Params
    ///     - tick_spacing
    ///     - new_fee_rate
    /// Returns
    public entry fun update_fee_tier(
        protocol_authority: &signer,
        tick_spacing: u64,
        new_fee_rate: u64
    ) {
        fee_tier::update_fee_tier(protocol_authority, tick_spacing, new_fee_rate);
    }

    #[cmd]
    /// Delete fee_tier.
    /// Params
    ///     - tick_spacing
    /// Returns
    public entry fun delete_fee_tier(
        protocol_authority: &signer,
        tick_spacing: u64,
    ) {
        fee_tier::delete_fee_tier(protocol_authority, tick_spacing);
    }

    #[cmd]
    /// Create a pool of clmmpool protocol. The pool is identified by (CoinTypeA, CoinTypeB, tick_spacing).
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - tick_spacing
    ///     - initialize_sqrt_price: the init sqrt price of the pool.
    ///     - uri: this uri is used for token uri of the position token of this pool.
    /// Returns
    public entry fun create_pool<CoinTypeA, CoinTypeB>(
        account: &signer,
        tick_spacing: u64,
        initialize_sqrt_price: u128,
        uri: String
    ) {
        factory::create_pool<CoinTypeA, CoinTypeB>(account, tick_spacing, initialize_sqrt_price, uri);
    }

    #[cmd]
    /// Add liquidity into a pool. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - pool_address
    ///     - delta_liquidity
    ///     - max_amount_a: the max number of coin_a can be consumed by the pool.
    ///     - max_amount_b: the max number of coin_b can be consumed by the pool.
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        max_amount_a: u64,
        max_amount_b: u64,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        index: u64,
    ) {
        // Open position if needed.
        let tick_lower_index = i64::from_u64(tick_lower);
        let tick_upper_index = i64::from_u64(tick_upper);
        let pos_index = if (is_open) {
            pool::open_position<CoinTypeA, CoinTypeB>(
                account,
                pool_address,
                tick_lower_index,
                tick_upper_index,
            )
        } else {
            pool::check_position_authority<CoinTypeA, CoinTypeB>(account, pool_address, index);
            let (position_tick_lower, position_tick_upper) =
                pool::get_position_tick_range<CoinTypeA, CoinTypeB>(pool_address, index);
            assert!(i64::eq(tick_lower_index, position_tick_lower), EIS_NOT_VALID_TICK);
            assert!(i64::eq(tick_upper_index, position_tick_upper), EIS_NOT_VALID_TICK);
            index
        };

        // Add liquidity
        let receipt = pool::add_liquidity<CoinTypeA, CoinTypeB>(
            pool_address,
            delta_liquidity,
            pos_index
        );
        let (amount_a_needed, amount_b_needed) = pool::add_liqudity_pay_amount(&receipt);
        assert!(amount_a_needed <= max_amount_a, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        assert!(amount_b_needed <= max_amount_b, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        let coin_a = if (amount_a_needed > 0) {
            coin::withdraw<CoinTypeA>(account, amount_a_needed)
        }else {
            coin::zero<CoinTypeA>()
        };
        let coin_b = if (amount_b_needed > 0) {
            coin::withdraw<CoinTypeB>(account, amount_b_needed)
        }else {
            coin::zero<CoinTypeB>()
        };
        pool::repay_add_liquidity(coin_a, coin_b, receipt);
    }

    #[cmd]
    /// Add liquidity into a pool. The position is identified by the name.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - pool_address
    ///     - amount_a: if fix_amount_a is false, amount_a is the max coin_a amount to be consumed.
    ///     - amount_b: if fix_amount_a is true, amount_b is the max coin_b amount to be consumed.
    ///     - fix_amount_a: control whether coin_a or coin_b amount is fixed
    ///     - tick_lower
    ///     - tick_upper
    ///     - is_open: control whether or not to create a new position or add liquidity on existed position.
    ///     - index: position index. if `is_open` is true, index is no use.
    /// Returns
    public entry fun add_liquidity_fix_token<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        tick_lower: u64,
        tick_upper: u64,
        is_open: bool,
        index: u64,
    ) {
        // Open position if needed.
        let tick_lower_index = i64::from_u64(tick_lower);
        let tick_upper_index = i64::from_u64(tick_upper);
        let pos_index = if (is_open) {
            pool::open_position<CoinTypeA, CoinTypeB>(
                account,
                pool_address,
                tick_lower_index,
                tick_upper_index,
            )
        } else {
            pool::check_position_authority<CoinTypeA, CoinTypeB>(account, pool_address, index);
            let (position_tick_lower, position_tick_upper) =
                pool::get_position_tick_range<CoinTypeA, CoinTypeB>(pool_address, index);
            assert!(i64::eq(tick_lower_index, position_tick_lower), EIS_NOT_VALID_TICK);
            assert!(i64::eq(tick_upper_index, position_tick_upper), EIS_NOT_VALID_TICK);
            index
        };

        // Add liquidity
        let amount = if (fix_amount_a) { amount_a } else { amount_b };
        let receipt = pool::add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
            pool_address,
            amount,
            fix_amount_a,
            pos_index
        );
        let (amount_a_needed, amount_b_needed) = pool::add_liqudity_pay_amount(&receipt);
        if (fix_amount_a) {
            assert!(amount_a == amount_a_needed && amount_b_needed <= amount_b, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        }else {
            assert!(amount_b == amount_b_needed && amount_a_needed <= amount_a, EAMOUNT_IN_ABOVE_MAX_LIMIT);
        };
        let coin_a = if (amount_a_needed > 0) {
            coin::withdraw<CoinTypeA>(account, amount_a_needed)
        }else {
            coin::zero<CoinTypeA>()
        };
        let coin_b = if (amount_b_needed > 0) {
            coin::withdraw<CoinTypeB>(account, amount_b_needed)
        }else {
            coin::zero<CoinTypeB>()
        };
        pool::repay_add_liquidity(coin_a, coin_b, receipt);
    }

    #[cmd]
    /// Remove liquidity from a pool.
    /// The position token is identified by (creator, collection, name), the creator is pool address.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - pool_address
    ///     - delta_liquidity
    ///     - min_amount_a
    ///     - min_amount_b
    ///     - position_index: the position index to remove liquidity.
    ///     - is_close: is or not to close the position if position is empty.
    /// Returns
    public entry fun remove_liquidity<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        delta_liquidity: u128,
        min_amount_a: u64,
        min_amount_b: u64,
        position_index: u64,
        is_close: bool,
    ) {
        // Remove liquidity
        let (coin_a, coin_b) = pool::remove_liquidity<CoinTypeA, CoinTypeB>(
            account,
            pool_address,
            delta_liquidity,
            position_index
        );
        let (amount_a_returned, amount_b_returned) = {
            (coin::value(&coin_a), coin::value(&coin_b))
        };
        assert!(amount_a_returned >= min_amount_a, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        assert!(amount_b_returned >= min_amount_b, EAMOUNT_OUT_BELOW_MIN_LIMIT);

        // Send coin to liquidity owner
        let user_address = signer::address_of(account);
        if (!coin::is_account_registered<CoinTypeA>(user_address)) {
            coin::register<CoinTypeA>(account);
        };
        if (!coin::is_account_registered<CoinTypeB>(user_address)) {
            coin::register<CoinTypeB>(account);
        };
        coin::deposit<CoinTypeA>(user_address, coin_a);
        coin::deposit<CoinTypeB>(user_address, coin_b);

        // Collect position's fee
        let (fee_coin_a, fee_coin_b) = pool::collect_fee<CoinTypeA, CoinTypeB>(
            account,
            pool_address,
            position_index,
            false
        );
        coin::deposit<CoinTypeA>(user_address, fee_coin_a);
        coin::deposit<CoinTypeB>(user_address, fee_coin_b);

        // Close position if is_close=true and position's liquidity is zero.
        if (is_close) {
            pool::checked_close_position<CoinTypeA, CoinTypeB>(account, pool_address, position_index);
        }
    }

    #[cmd]
    /// Provide to close position if position is empty.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - pool_address: The pool account address
    ///     - position_index: The position iindex
    /// Returns
    public entry fun close_position<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        position_index: u64,
    ) {
        let is_closed = pool::checked_close_position<CoinTypeA, CoinTypeB>(
            account,
            pool_address,
            position_index
        );
        if (!is_closed) {
            abort EPOSITION_IS_NOT_ZERO
        };
    }

    #[cmd]
    /// Provide to the position to collect the fee of the position earned.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - pool_address: The pool account address
    ///     - position_index: The position index
    /// Returns
    public entry fun collect_fee<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        position_index: u64
    ) {
        let user_address = signer::address_of(account);
        let (fee_coin_a, fee_coin_b) = pool::collect_fee<CoinTypeA, CoinTypeB>(
            account,
            pool_address,
            position_index,
            true
        );
        if (!coin::is_account_registered<CoinTypeA>(user_address)) {
            coin::register<CoinTypeA>(account);
        };
        if (!coin::is_account_registered<CoinTypeB>(user_address)) {
            coin::register<CoinTypeB>(account);
        };
        coin::deposit<CoinTypeA>(user_address, fee_coin_a);
        coin::deposit<CoinTypeB>(user_address, fee_coin_b);
    }

    #[cmd]
    /// Provide to the position to collect the rewarder of the position earned.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///         - CoinTypeC
    ///     - pool_address: pool address.
    ///     - rewarder_index: the rewarder index(0,1,2).
    ///     - pos_index: the position index to collect rewarder.
    /// Returns
    public entry fun collect_rewarder<CoinTypeA, CoinTypeB, CoinTypeC>(
        account: &signer,
        pool_address: address,
        rewarder_index: u8,
        pos_index: u64
    ) {
        let user_address = signer::address_of(account);
        let rewarder_coin = pool::collect_rewarder<CoinTypeA, CoinTypeB, CoinTypeC>(
            account,
            pool_address,
            pos_index,
            rewarder_index,
            true
        );
        if (!coin::is_account_registered<CoinTypeC>(user_address)) {
            coin::register<CoinTypeC>(account);
        };
        coin::deposit<CoinTypeC>(user_address, rewarder_coin);
    }

    #[cmd]
    /// Provide to protocol_claim_authority to collect protocol fee.
    /// Params
    ///     Type:
    ///         - CoinTypeA
    ///         - CoinTypeB
    ///     - account The protocol fee claim authority
    ///     - pool_address The pool account address
    /// Returns
    public entry fun collect_protocol_fee<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address
    ) {
        let addr = signer::address_of(account);
        let (coin_a, coin_b) = pool::collect_protocol_fee<CoinTypeA, CoinTypeB>(
            account,
            pool_address
        );
        if (!coin::is_account_registered<CoinTypeA>(addr)) {
            coin::register<CoinTypeA>(account);
        };
        if (!coin::is_account_registered<CoinTypeB>(addr)) {
            coin::register<CoinTypeB>(account);
        };
        coin::deposit<CoinTypeA>(addr, coin_a);
        coin::deposit<CoinTypeB>(addr, coin_b);
    }

    #[cmd]
    /// Swap.
    /// Params
    ///     - account The swap tx signer
    ///     - pool_address: The pool account address
    ///     - a_to_b: true --> atob; false --> btoa
    ///     - by_amount_in: represent `amount` is the input(if a_to_b is true, then input is coin_a) amount to be consumed or output amount returned.
    ///     - amount
    ///     - amount_limit: if `by_amount_in` is true, `amount_limit` is the minimum outout amount returned;
    ///                     if `by_amount_in` is false, `amount_limit` is the maximum input amount can be consumed.
    ///     - sqrt_price_limit
    ///     - partner: The partner name
    /// Returns
    public entry fun swap<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_address: address,
        a_to_b: bool,
        by_amount_in: bool,
        amount: u64,
        amount_limit: u64,
        sqrt_price_limit: u128,
        partner: String,
    ) {
        let swap_from = signer::address_of(account);
        let (coin_a, coin_b, flash_receipt) = pool::flash_swap<CoinTypeA, CoinTypeB>(
            pool_address,
            swap_from,
            partner,
            a_to_b,
            by_amount_in,
            amount,
            sqrt_price_limit,
        );
        let in_amount = pool::swap_pay_amount(&flash_receipt);
        let out_amount = if (a_to_b) {
            coin::value(&coin_b)
        }else {
            coin::value(&coin_a)
        };

        //check limit
        if (by_amount_in) {
            assert!(in_amount == amount, ESWAP_AMOUNT_INCORRECT);
            assert!(out_amount >= amount_limit, EAMOUNT_OUT_BELOW_MIN_LIMIT);
        }else {
            assert!(out_amount == amount, ESWAP_AMOUNT_INCORRECT);
            assert!(in_amount <= amount_limit, EAMOUNT_IN_ABOVE_MAX_LIMIT)
        };

        //repay coin
        if (a_to_b) {
            if (!coin::is_account_registered<CoinTypeB>(swap_from)) {
                coin::register<CoinTypeB>(account);
            };
            coin::destroy_zero(coin_a);
            coin::deposit<CoinTypeB>(swap_from, coin_b);
            let coin_a = coin::withdraw<CoinTypeA>(account, in_amount);
            pool::repay_flash_swap<CoinTypeA, CoinTypeB>(coin_a, coin::zero<CoinTypeB>(), flash_receipt);
        }else {
            if (!coin::is_account_registered<CoinTypeA>(swap_from)) {
                coin::register<CoinTypeA>(account);
            };
            coin::destroy_zero(coin_b);
            coin::deposit<CoinTypeA>(swap_from, coin_a);
            let coin_b = coin::withdraw<CoinTypeB>(account, in_amount);
            pool::repay_flash_swap<CoinTypeA, CoinTypeB>(coin::zero<CoinTypeA>(), coin_b, flash_receipt);
        }
    }

    #[cmd]
    /// Provide to the protocol_authority to update the pool fee rate.
    /// Params
    ///     - pool_address
    ///     - new_fee_rate
    /// Returns
    public entry fun update_fee_rate<CoinTypeA, CoinTypeB>(
        protocol_authority: &signer,
        pool_addr: address,
        new_fee_rate: u64
    ) {
        pool::update_fee_rate<CoinTypeA, CoinTypeB>(protocol_authority, pool_addr, new_fee_rate);
    }


    #[cmd]
    /// Initialize the rewarder.
    /// Params
    ///     - account The protocol authority signer
    ///     - pool_address The pool account address
    ///     - authority The rewarder authority address
    ///     - index The rewarder index
    /// Returns
    public entry fun initialize_rewarder<CoinTypeA, CoinTypeB, CoinTypeC>(
        account: &signer,
        pool_address: address,
        authority: address,
        index: u64,
    ) {
        pool::initialize_rewarder<CoinTypeA, CoinTypeB, CoinTypeC>(account, pool_address, authority, index);
    }

    #[cmd]
    /// Update the rewarder emission.
    /// Params
    ///     - pool_address
    ///     - index
    ///     - emission_per_second
    /// Returns
    public entry fun update_rewarder_emission<CoinTypeA, CoinTypeB, CoinTypeC>(
        account: &signer,
        pool_address: address,
        index: u8,
        emission_per_second: u128
    ) {
        pool::update_emission<CoinTypeA, CoinTypeB, CoinTypeC>(account, pool_address, index, emission_per_second);
    }

    #[cmd]
    /// Transfer the authority of a rewarder.
    /// Params
    ///     - pool_address
    ///     - index
    ///     - new_authority
    /// Returns
    public entry fun transfer_rewarder_authority<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_addr: address,
        index: u8,
        new_authority: address
    ) {
        pool::transfer_rewarder_authority<CoinTypeA, CoinTypeB>(account, pool_addr, index, new_authority);
    }

    #[cmd]
    /// Accept the authority of a rewarder.
    /// Params
    ///     - pool_address
    ///     - index
    /// Returns
    public entry fun accept_rewarder_authority<CoinTypeA, CoinTypeB>(
        account: &signer,
        pool_addr: address,
        index: u8,
    ) {
        pool::accept_rewarder_authority<CoinTypeA, CoinTypeB>(account, pool_addr, index);
    }

    #[cmd]
    /// Create a partner.
    /// The partner is identified by name.
    /// Params
    ///     - fee_rate
    ///     - name: partner name.
    ///     - receiver: the partner authority to claim the partner fee.
    ///     - start_time: partner valid start time.
    ///     - end_time: partner valid end time.
    /// Returns
    public entry fun create_partner(
        account: &signer,
        name: String,
        fee_rate: u64,
        receiver: address,
        start_time: u64,
        end_time: u64
    ) {
        partner::create_partner(account, name, fee_rate, receiver, start_time, end_time);
    }

    #[cmd]
    /// Update the fee_rate of a partner.
    /// Params
    ///     - name
    ///     - new_fee_rate
    /// Returns
    public entry fun update_partner_fee_rate(protocol_authority: &signer, name: String, new_fee_rate: u64) {
        partner::update_fee_rate(protocol_authority, name, new_fee_rate);
    }

    #[cmd]
    /// Update the time of a partner.
    /// Params
    ///     - name
    ///     - start_time
    ///     - end_time
    /// Returns
    public entry fun update_partner_time(protocol_authority: &signer, name: String, start_time: u64, end_time: u64) {
        partner::update_time(protocol_authority, name, start_time, end_time);
    }

    #[cmd]
    /// Transfer the receiver of a partner.
    /// Params
    ///     - name
    ///     - new_receiver
    /// Returns
    public entry fun transfer_partner_receiver(account: &signer, name: String, new_recevier: address) {
        partner::transfer_receiver(account, name, new_recevier);
    }

    #[cmd]
    /// Accept the recevier of a partner.
    /// Params
    ///     - name
    /// Returns
    public entry fun accept_partner_receiver(account: &signer, name: String) {
        partner::accept_receiver(account, name);
    }

    #[cmd]
    /// Pause the Protocol.
    /// Params
    /// Returns
    public entry fun pause(protocol_authority: &signer) {
        config::pause(protocol_authority);
    }

    #[cmd]
    /// Unpause the Protocol.
    /// Params
    /// Returns
    public entry fun unpause(protocol_authority: &signer) {
        config::unpause(protocol_authority);
    }

    #[cmd]
    /// Pause an pool.
    /// Params
    ///     - pool_address: address
    /// Returns
    public entry fun pause_pool<CoinTypeA, CoinTypeB>(protocol_authority: &signer, pool_address: address) {
        pool::pause<CoinTypeA, CoinTypeB>(protocol_authority, pool_address);
    }

    #[cmd]
    /// Unpause an pool.
    /// Params
    ///     - pool_address: address
    /// Returns
    public entry fun unpause_pool<CoinTypeA, CoinTypeB>(protocol_authority: &signer, pool_address: address) {
        pool::unpause<CoinTypeA, CoinTypeB>(protocol_authority, pool_address);
    }

    #[cmd]
    /// Claim partner's ref fee
    /// Params
    ///     - account: The partner receiver account signer
    ///     - name: The partner name
    /// Returns
    public entry fun claim_ref_fee<CoinType>(account: &signer, name: String) {
        partner::claim_ref_fee<CoinType>(account, name)
    }

    #[cmd]
    /// Init clmm acl
    /// Params
    ///    - account: The clmmpool deployer
    public entry fun init_clmm_acl(account: &signer) {
        config::init_clmm_acl(account)
    }

    #[cmd]
    /// Update the pool's position nft collection and token uri.
    /// Params
    ///     - account: The setter account signer
    ///     - pool_address: The pool address
    ///     - uri: The nft uri
    /// Returns
    public entry fun update_pool_uri<CoinTypeA, CoinTypeB>(account: &signer, pool_address: address, uri: String) {
        pool::update_pool_uri<CoinTypeA, CoinTypeB>(account, pool_address, uri)
    }

    #[cmd]
    /// Add role in clmm acl
    /// Params
    ///     - account: The protocol authority signer
    ///     - member: The role member address
    ///     - role: The role
    /// Returns
    public entry fun add_role(account: &signer, member: address, role: u8) {
        config::add_role(account, member, role)
    }

    #[cmd]
    /// Add role in clmm acl
    /// Params
    ///     - account: The protocol authority signer
    ///     - member: The role member address
    ///     - role: The role
    /// Returns
    public entry fun remove_role(account: &signer, member: address, role: u8) {
        config::remove_role(account, member, role)
    }
}
