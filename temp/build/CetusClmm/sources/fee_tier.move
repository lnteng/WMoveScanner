/// The FeeTiers info provide the fee_tier metadata used when create pool.
/// The FeeTier is stored in the deployed account(@cetus_clmm).
/// The FeeTier is identified by the tick_spacing.
/// The FeeTier can only be created and updated by the protocol.

module cetus_clmm::fee_tier {
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use cetus_clmm::config;

    /// Max swap fee rate(100000 = 200000/1000000 = 20%)
    const MAX_FEE_RATE: u64 = 200000;

    /// Errors
    const EFEE_TIER_ALREADY_EXIST: u64 = 1;
    const EFEE_TIER_NOT_FOUND: u64 = 2;
    const EFEETIER_ALREADY_INITIALIZED: u64 = 3;
    const EINVALID_FEE_RATE: u64 = 4;

    /// The clmmpools fee tier data
    struct FeeTier has store, copy, drop {
        /// The tick spacing
        tick_spacing: u64,

        /// The default fee rate
        fee_rate: u64,
    }

    /// The clmmpools fee tier map
    struct FeeTiers has key {
        fee_tiers: SimpleMap<u64, FeeTier>,
        add_events: EventHandle<AddEvent>,
        update_events: EventHandle<UpdateEvent>,
        delete_events: EventHandle<DeleteEvent>,
    }

    struct AddEvent has drop, store {
        tick_spacing: u64,
        fee_rate: u64,
    }

    struct UpdateEvent has drop, store {
        tick_spacing: u64,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    struct DeleteEvent has drop, store {
        tick_spacing: u64,
    }

    /// initialize the global FeeTier of cetus clmm protocol
    public fun initialize(
        account: &signer,
    ) {
        config::assert_initialize_authority(account);
        move_to(account, FeeTiers {
            fee_tiers: simple_map::create<u64, FeeTier>(),
            add_events: account::new_event_handle<AddEvent>(account),
            update_events: account::new_event_handle<UpdateEvent>(account),
            delete_events: account::new_event_handle<DeleteEvent>(account),
        });
    }

    /// Add a fee tier
    public fun add_fee_tier(
        account: &signer,
        tick_spacing: u64,
        fee_rate: u64
    ) acquires FeeTiers {
        assert!(fee_rate <= MAX_FEE_RATE, EINVALID_FEE_RATE);

        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@cetus_clmm);
        assert!(
            !simple_map::contains_key(&fee_tiers.fee_tiers, &tick_spacing),
            EFEE_TIER_ALREADY_EXIST
        );
        simple_map::add(&mut fee_tiers.fee_tiers, tick_spacing, FeeTier {
            tick_spacing,
            fee_rate
        });
        event::emit_event(&mut fee_tiers.add_events, AddEvent {
            tick_spacing,
            fee_rate,
        })
    }

    /// Update the default fee rate
    public fun update_fee_tier(
        account: &signer,
        tick_spacing: u64,
        new_fee_rate: u64,
    ) acquires FeeTiers {
        assert!(new_fee_rate <= MAX_FEE_RATE, EINVALID_FEE_RATE);

        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@cetus_clmm);
        assert!(
            simple_map::contains_key(&fee_tiers.fee_tiers, &tick_spacing),
            EFEE_TIER_NOT_FOUND
        );

        let fee_tier = simple_map::borrow_mut(&mut fee_tiers.fee_tiers, &tick_spacing);
        let old_fee_rate = fee_tier.fee_rate;
        fee_tier.fee_rate = new_fee_rate;
        event::emit_event(&mut fee_tiers.update_events, UpdateEvent {
            tick_spacing,
            old_fee_rate,
            new_fee_rate
        });
    }

    /// Delete fee_tier
    public fun delete_fee_tier(
        account: &signer,
        tick_spacing: u64,
    ) acquires FeeTiers {
        config::assert_protocol_authority(account);
        let fee_tiers = borrow_global_mut<FeeTiers>(@cetus_clmm);
        assert!(
            simple_map::contains_key(&fee_tiers.fee_tiers, &tick_spacing),
            EFEE_TIER_NOT_FOUND
        );
        simple_map::remove(&mut fee_tiers.fee_tiers, &tick_spacing);
        event::emit_event(&mut fee_tiers.delete_events, DeleteEvent {
            tick_spacing
        });
    }

    /// Get fee rate by tick spacing
    public fun get_fee_rate(tick_spacing: u64): u64 acquires FeeTiers {
        let fee_tiers = &borrow_global<FeeTiers>(@cetus_clmm).fee_tiers;
        assert!(
            simple_map::contains_key(fee_tiers, &tick_spacing),
            EFEE_TIER_NOT_FOUND
        );
        let fee_tier = simple_map::borrow(fee_tiers, &tick_spacing);
        fee_tier.fee_rate
    }

    public fun max_fee_rate(): u64 {
        MAX_FEE_RATE
    }
}
