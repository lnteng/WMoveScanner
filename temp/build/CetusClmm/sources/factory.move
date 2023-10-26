module cetus_clmm::factory {
    use std::bcs;
    use std::signer;
    use std::string::{Self, String, length};
    use std::option;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::comparator;
    use aptos_std::type_info::{TypeInfo, type_of};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use cetus_clmm::tick_math;
    use cetus_clmm::utils;
    use cetus_clmm::pool;
    use cetus_clmm::config;
    use cetus_clmm::fee_tier;
    use cetus_clmm::partner;

    /// Consts
    const POOL_OWNER_SEED: vector<u8> = b"CetusPoolOwner";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Cetus Liquidity Position";
    const POOL_DEFAULT_URI: vector<u8> = b"https://edbz27ws6curuggjavd2ojwm4td2se5x53elw2rbo3rwwnshkukq.arweave.net/IMOdftLwqRoYyQVHpybM5MepE7fuyLtqIXbjazZHVRU";

    /// Errors
    const EPOOL_ALREADY_INITIALIZED: u64 = 1;
    const EINVALID_SQRTPRICE: u64 = 2;

    /// For support create pool by anyone, PoolOwner store a resource account signer_cap
    struct PoolOwner has key {
        signer_capability: account::SignerCapability,
    }

    struct PoolId has store, copy, drop {
        coin_type_a: TypeInfo,
        coin_type_b: TypeInfo,
        tick_spacing: u64
    }

    /// Store the pools metadata info in the deployed(@cetus_clmm) account.
    struct Pools has key {
        data: SimpleMap<PoolId, address>,
        create_pool_events: EventHandle<CreatePoolEvent>,
        index: u64,
    }

    struct CreatePoolEvent has drop, store {
        creator: address,
        pool_address: address,
        position_collection_name: String,
        coin_type_a: TypeInfo,
        coin_type_b: TypeInfo,
        tick_spacing: u64
    }

    ///
    fun init_module(
        account: &signer
    ) {
        move_to(account, Pools {
            data: simple_map::create<PoolId, address>(),
            create_pool_events: account::new_event_handle<CreatePoolEvent>(account),
            index: 0,
        });

        let (_, signer_cap) = account::create_resource_account(account, POOL_OWNER_SEED);
        move_to(account, PoolOwner {
            signer_capability: signer_cap,
        });
        config::initialize(account);
        fee_tier::initialize(account);
        partner::initialize(account);
    }

    public fun create_pool<CoinTypeA, CoinTypeB>(
        account: &signer,
        tick_spacing: u64,
        initialize_price: u128,
        uri: String
    ): address acquires PoolOwner, Pools {
        config::assert_pool_create_authority(account);

        let uri = if (length(&uri) == 0 || !config::allow_set_position_nft_uri(account)) {
            string::utf8(POOL_DEFAULT_URI)
        } else {
            uri
        };

        assert!(
            initialize_price >= tick_math::min_sqrt_price() && initialize_price <= tick_math::max_sqrt_price(),
            EINVALID_SQRTPRICE
        );

        // Create pool account
        let pool_id = new_pool_id<CoinTypeA, CoinTypeB>(tick_spacing);
        let pool_owner = borrow_global<PoolOwner>(@cetus_clmm);
        let pool_owner_signer = account::create_signer_with_capability(&pool_owner.signer_capability);

        let pool_seed = new_pool_seed<CoinTypeA, CoinTypeB>(tick_spacing);
        let pool_seed = bcs::to_bytes<PoolId>(&pool_seed);
        let (pool_signer, signer_cap) = account::create_resource_account(&pool_owner_signer, pool_seed);
        let pool_address = signer::address_of(&pool_signer);

        let pools = borrow_global_mut<Pools>(@cetus_clmm);
        pools.index = pools.index + 1;
        assert!(
            !simple_map::contains_key<PoolId, address>(&pools.data, &pool_id),
            EPOOL_ALREADY_INITIALIZED
        );
        simple_map::add<PoolId, address>(&mut pools.data, pool_id, pool_address);

        // Initialize pool's metadata
        let position_collection_name = pool::new<CoinTypeA, CoinTypeB>(
            &pool_signer,
            tick_spacing,
            initialize_price,
            pools.index,
            uri,
            signer_cap
        );

        event::emit_event(&mut pools.create_pool_events, CreatePoolEvent {
            coin_type_a: type_of<CoinTypeA>(),
            coin_type_b: type_of<CoinTypeB>(),
            tick_spacing,
            creator: signer::address_of(account),
            pool_address,
            position_collection_name
        });
        pool_address
    }

    public fun get_pool<CoinTypeA, CoinTypeB>(
        tick_spacing: u64
    ): option::Option<address> acquires Pools {
        let pools = borrow_global<Pools>(@cetus_clmm);
        let pool_id = new_pool_id<CoinTypeA, CoinTypeB>(tick_spacing);
        if (simple_map::contains_key(&pools.data, &pool_id)) {
            return option::some(*simple_map::borrow(&pools.data, &pool_id))
        };
        option::none<address>()
    }

    fun new_pool_id<CoinTypeA, CoinTypeB>(tick_spacing: u64): PoolId {
        PoolId {
            coin_type_a: type_of<CoinTypeA>(),
            coin_type_b: type_of<CoinTypeB>(),
            tick_spacing
        }
    }

    fun new_pool_seed<CoinTypeA, CoinTypeB>(tick_spacing: u64): PoolId {
        if (comparator::is_smaller_than(&utils::compare_coin<CoinTypeA, CoinTypeB>())) {
            PoolId {
                coin_type_a: type_of<CoinTypeA>(),
                coin_type_b: type_of<CoinTypeB>(),
                tick_spacing
            }
        } else {
            PoolId {
                coin_type_a: type_of<CoinTypeB>(),
                coin_type_b: type_of<CoinTypeA>(),
                tick_spacing
            }
        }
    }
}
