/// The global config is initialized only once and store the protocol_authority, protocol_fee_claim_authority,
/// pool_create_authority and protocol_fee_rate.
/// The protocol_authority control the protocol, can update the protocol_fee_claim_authority, pool_create_authority and
/// protocol_fee_rate, and can be tranfered to others.
module cetus_clmm::config {
    use std::signer;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use cetus_clmm::acl::{Self, ACL};


    friend cetus_clmm::factory;

    /// Consts
    const DEFAULT_ADDRESS: address = @0x0;
    const MAX_PROTOCOL_FEE_RATE: u64 = 3000;
    const DEFAULT_PROTOCOL_FEE_RATE: u64 = 2000;

    /// Errors
    const ENOT_HAS_PRIVILEGE: u64 = 1;
    const ECONFIG_ALREADY_INITIALIZED: u64 = 2;
    const EINVALID_PROTOCOL_FEE_RATE: u64 = 3;
    const EPROTOCOL_IS_PAUSED: u64 = 4;
    const EINVALID_ACL_ROLE: u64 = 5;

    /// Roles
    const ROLE_SET_POSITION_NFT_URI: u8 = 1;
    const ROLE_RESET_INIT_SQRT_PRICE: u8 = 2;

    /// The clmmpools global config
    struct GlobalConfig has key {
        /// The authority to control the config and clmmpools related to this clmmconfig.
        protocol_authority: address,

        /// `protocol_pending_authority` is used when transfer protocol authority, store the new authority to accept in next step and as the new authority.
        protocol_pending_authority: address,

        /// `protocol_fee_claim_authority` is used when claim the protocol fee.
        protocol_fee_claim_authority: address,

        /// `pool_create_authority` is used when create pool. if this address is Default it means everyone can create the pool.
        pool_create_authority: address,

        /// `fee_rate` The protocol fee rate
        protocol_fee_rate: u64,

        is_pause: bool,
        /// Events.
        transfer_auth_events: EventHandle<TransferAuthEvent>,
        accept_auth_events: EventHandle<AcceptAuthEvent>,
        update_claim_auth_events: EventHandle<UpdateClaimAuthEvent>,
        update_pool_create_events: EventHandle<UpdatePoolCreateEvent>,
        update_fee_rate_events: EventHandle<UpdateFeeRateEvent>,
    }

    struct ClmmACL has key {
        acl: ACL
    }

    /// Events.
    struct TransferAuthEvent has drop, store {
        old_auth: address,
        new_auth: address,
    }

    struct AcceptAuthEvent has drop, store {
        old_auth: address,
        new_auth: address,
    }

    struct UpdateClaimAuthEvent has drop, store {
        old_auth: address,
        new_auth: address,
    }

    struct UpdatePoolCreateEvent has drop, store {
        old_auth: address,
        new_auth: address,
    }

    struct UpdateFeeRateEvent has drop, store {
        old_fee_rate: u64,
        new_fee_rate: u64,
    }


    /// initialize the global config of cetus clmm protocol
    public fun initialize(
        account: &signer,
    ) {
        assert_initialize_authority(account);
        let deployer = @cetus_clmm;
        move_to(account, GlobalConfig {
            protocol_authority: deployer,
            protocol_pending_authority: DEFAULT_ADDRESS,
            protocol_fee_claim_authority: deployer,
            pool_create_authority: DEFAULT_ADDRESS,
            protocol_fee_rate: DEFAULT_PROTOCOL_FEE_RATE,
            is_pause: false,
            transfer_auth_events: account::new_event_handle<TransferAuthEvent>(account),
            accept_auth_events: account::new_event_handle<AcceptAuthEvent>(account),
            update_claim_auth_events: account::new_event_handle<UpdateClaimAuthEvent>(account),
            update_pool_create_events: account::new_event_handle<UpdatePoolCreateEvent>(account),
            update_fee_rate_events: account::new_event_handle<UpdateFeeRateEvent>(account),
        });
    }

    /// Transfer the protocol authority
    public fun transfer_protocol_authority(
        account: &signer,
        protocol_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        global_config.protocol_pending_authority = protocol_authority;
        event::emit_event(&mut global_config.transfer_auth_events, TransferAuthEvent {
            old_auth: global_config.protocol_authority,
            new_auth: protocol_authority,
        });
    }

    /// Accept the protocol authority protocol authority
    public fun accept_protocol_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        assert!(
            global_config.protocol_pending_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
        let old_auth = global_config.protocol_authority;
        global_config.protocol_authority = signer::address_of(account);
        global_config.protocol_pending_authority = DEFAULT_ADDRESS;
        event::emit_event(&mut global_config.accept_auth_events, AcceptAuthEvent {
            old_auth,
            new_auth: global_config.protocol_authority
        });
    }

    /// Update the protocol fee claim authority
    public fun update_protocol_fee_claim_authority(
        account: &signer,
        protocol_fee_claim_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        let old_auth = global_config.protocol_fee_claim_authority;
        global_config.protocol_fee_claim_authority = protocol_fee_claim_authority;
        event::emit_event(&mut global_config.update_claim_auth_events, UpdateClaimAuthEvent {
            old_auth,
            new_auth: global_config.protocol_fee_claim_authority
        });
    }

    /// Update the pool create authority
    public fun update_pool_create_authority(
        account: &signer,
        pool_create_authority: address
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        let old_auth = global_config.pool_create_authority;
        global_config.pool_create_authority = pool_create_authority;
        event::emit_event(&mut global_config.update_pool_create_events, UpdatePoolCreateEvent {
            old_auth,
            new_auth: global_config.pool_create_authority
        });
    }

    /// Update the protocol fee rate
    public fun update_protocol_fee_rate(
        account: &signer,
        protocol_fee_rate: u64
    ) acquires GlobalConfig {
        assert_protocol_authority(account);
        assert!(protocol_fee_rate <= MAX_PROTOCOL_FEE_RATE, EINVALID_PROTOCOL_FEE_RATE);
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        let old_fee_rate = global_config.protocol_fee_rate;
        global_config.protocol_fee_rate = protocol_fee_rate;
        event::emit_event(&mut global_config.update_fee_rate_events, UpdateFeeRateEvent {
            old_fee_rate,
            new_fee_rate: protocol_fee_rate
        });
    }


    public fun pause(account: &signer) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        global_config.is_pause = true;
    }

    public fun unpause(account: &signer) acquires GlobalConfig {
        assert_protocol_authority(account);
        let global_config = borrow_global_mut<GlobalConfig>(@cetus_clmm);
        global_config.is_pause = false;
    }

    public fun assert_protocol_status() acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@cetus_clmm);
        if (global_config.is_pause) {
            abort EPROTOCOL_IS_PAUSED
        }
    }

    /// Get protocol fee rate
    public fun get_protocol_fee_rate(): u64 acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@cetus_clmm);
        global_config.protocol_fee_rate
    }

    public fun assert_initialize_authority(account: &signer) {
        assert!(
            signer::address_of(account) == @cetus_clmm,
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun assert_protocol_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@cetus_clmm);
        assert!(
            global_config.protocol_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun assert_protocol_fee_claim_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@cetus_clmm);
        assert!(
            global_config.protocol_fee_claim_authority == signer::address_of(account),
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun assert_pool_create_authority(account: &signer) acquires GlobalConfig {
        let global_config = borrow_global<GlobalConfig>(@cetus_clmm);
        assert!(
            (
                global_config.pool_create_authority == signer::address_of(account) ||
                    global_config.pool_create_authority == DEFAULT_ADDRESS
            ),
            ENOT_HAS_PRIVILEGE
        );
    }

    public fun init_clmm_acl(account: &signer) {
        assert_initialize_authority(account);
        move_to(account, ClmmACL{
            acl: acl::new()
        })
    }

    public fun add_role(account: &signer, member: address, role: u8) acquires GlobalConfig, ClmmACL {
        assert!(role == ROLE_SET_POSITION_NFT_URI || role == ROLE_RESET_INIT_SQRT_PRICE, EINVALID_ACL_ROLE);
        assert_protocol_authority(account);
        let clmm_acl = borrow_global_mut<ClmmACL>(@cetus_clmm);
        acl::add_role(&mut clmm_acl.acl, member, role)
    }

    public fun remove_role(account: &signer, member: address, role: u8) acquires GlobalConfig, ClmmACL {
        assert!(role == ROLE_SET_POSITION_NFT_URI || role == ROLE_RESET_INIT_SQRT_PRICE, EINVALID_ACL_ROLE);
        assert_protocol_authority(account);
        let clmm_acl = borrow_global_mut<ClmmACL>(@cetus_clmm);
        acl::remove_role(&mut clmm_acl.acl, member, role)
    }

    public fun allow_set_position_nft_uri(
        account: &signer
    ) : bool acquires ClmmACL {
        let clmm_acl = borrow_global<ClmmACL>(@cetus_clmm);
        acl::has_role(&clmm_acl.acl, signer::address_of(account), ROLE_SET_POSITION_NFT_URI)
    }

    public fun assert_reset_init_price_authority(
        account: &signer
    ) acquires ClmmACL {
        let clmm_acl = borrow_global<ClmmACL>(@cetus_clmm);
        if (!acl::has_role(&clmm_acl.acl, signer::address_of(account), ROLE_RESET_INIT_SQRT_PRICE)) {
            abort ENOT_HAS_PRIVILEGE
        }
    }
}