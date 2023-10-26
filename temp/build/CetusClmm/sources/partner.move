/// The partner module provide the ability to the thrid party to share part of protocol fee, when swaping through clmmpool.
/// The partner is created and controled by the protocol.
/// The partner is identified by name.
/// The partner is valided by start_time and end_time.
/// The partner fee is received by receiver.
/// The receiver can transfer the receiver address to other address.
/// The partner fee_rate, start_time and end_time can be update by the protocol.

module cetus_clmm::partner {
    use std::string::String;
    use std::signer;
    use aptos_std::type_info::{TypeInfo, type_of};
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::EventHandle;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use std::string;
    use aptos_std::table::Table;
    use aptos_std::table;
    use cetus_clmm::config;

    const PARTNER_RATE_DENOMINATOR: u64 = 10000;
    const DEFAULT_ADDRESS: address = @0x0;
    const MAX_PARTNER_FEE_RATE: u64 = 10000;

    /// Errors
    const EPARTNER_ALREADY_INITIALIZED: u64 = 1;
    const EPARTNER_ALREADY_EXISTED: u64 = 2;
    const EPARTNER_NOT_EXISTED: u64 = 3;
    const EINVALID_RECEIVER: u64 = 4;
    const EINVALID_TIME: u64 = 5;
    const EINVALID_PARTNER_FEE_RATE: u64 = 6;
    const EINVALID_PARTNER_NAME: u64 = 7;

    /// The Partners map
    struct Partners has key {
        data: Table<String, Partner>,
        create_events: EventHandle<CreateEvent>,
        update_fee_rate_events: EventHandle<UpdateFeeRateEvent>,
        update_time_events: EventHandle<UpdateTimeEvent>,
        transfer_receiver_events: EventHandle<TransferReceiverEvent>,
        accept_receiver_events: EventHandle<AcceptReceiverEvent>,
        receive_ref_fee_events: EventHandle<ReceiveRefFeeEvent>,
        claim_ref_fee_events: EventHandle<ClaimRefFeeEvent>,
    }

    struct PartnerMetadata has store, copy, drop {
        partner_address: address,
        receiver: address,
        pending_receiver: address,
        fee_rate: u64,
        start_time: u64,
        end_time: u64,
    }

    /// The Partner.
    struct Partner has store {
        metadata: PartnerMetadata,
        signer_capability: account::SignerCapability,
    }

    struct CreateEvent has drop, store {
        partner_address: address,
        fee_rate: u64,
        name: String,
        receiver: address,
        start_time: u64,
        end_time: u64,
    }

    struct UpdateFeeRateEvent has drop, store {
        name: String,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    struct UpdateTimeEvent has drop, store {
        name: String,
        start_time: u64,
        end_time: u64,
    }

    struct TransferReceiverEvent has drop, store {
        name: String,
        old_receiver: address,
        new_receiver: address
    }

    struct AcceptReceiverEvent has drop, store {
        name: String,
        receiver: address
    }

    struct ReceiveRefFeeEvent has drop, store {
        name: String,
        amount: u64,
        coin_type: TypeInfo,
    }

    struct ClaimRefFeeEvent has drop, store {
        name: String,
        receiver: address,
        coin_type: TypeInfo,
        amount: u64
    }

    public fun partner_fee_rate_denominator(): u64 {
        PARTNER_RATE_DENOMINATOR
    }

    /// Initialize the partner in @cetus_clmm account.
    /// Params
    /// Return
    ///
    public fun initialize(account: &signer) {
        config::assert_initialize_authority(account);
        move_to(account, Partners {
            data: table::new<String, Partner>(),
            create_events: account::new_event_handle<CreateEvent>(account),
            update_fee_rate_events: account::new_event_handle<UpdateFeeRateEvent>(account),
            update_time_events: account::new_event_handle<UpdateTimeEvent>(account),
            transfer_receiver_events: account::new_event_handle<TransferReceiverEvent>(account),
            accept_receiver_events: account::new_event_handle<AcceptReceiverEvent>(account),
            receive_ref_fee_events: account::new_event_handle<ReceiveRefFeeEvent>(account),
            claim_ref_fee_events: account::new_event_handle<ClaimRefFeeEvent>(account)
        })
    }

    /// Create a partner, identified by name
    /// Params
    ///     - fee_rate
    ///     - name: partner name.
    ///     - receiver: receiver address used for receive coin.
    ///     - start_time
    ///     - end_time
    /// Return
    ///
    public fun create_partner(
        account: &signer,
        name: String,
        fee_rate: u64,
        receiver: address,
        start_time: u64,
        end_time: u64,
    ) acquires Partners {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(end_time > timestamp::now_seconds(), EINVALID_TIME);
        assert!(fee_rate < MAX_PARTNER_FEE_RATE, EINVALID_PARTNER_FEE_RATE);
        assert!(!string::is_empty(&name), EINVALID_PARTNER_NAME);

        config::assert_protocol_authority(account);
        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(!table::contains(&partners.data, name), EPARTNER_ALREADY_EXISTED);
        let (partner_signer, signer_capability) = account::create_resource_account(
            account,
            *string::bytes(&name)
        );
        let partner_address = signer::address_of(&partner_signer);
        table::add(&mut partners.data, name, Partner {
            metadata: PartnerMetadata {
                receiver,
                pending_receiver: DEFAULT_ADDRESS,
                fee_rate,
                start_time,
                end_time,
                partner_address,
            },
            signer_capability,
        });
        event::emit_event<CreateEvent>(&mut partners.create_events, CreateEvent {
            partner_address,
            fee_rate,
            name,
            receiver,
            start_time,
            end_time,
        });
    }

    /// Update the partner fee_rate by protocol_fee_authority
    /// Params
    ///     - name: partner name.
    ///     - new_fee_rate
    /// Return
    ///
    public fun update_fee_rate(
        account: &signer,
        name: String,
        new_fee_rate: u64
    ) acquires Partners {
        assert!(new_fee_rate < MAX_PARTNER_FEE_RATE, EINVALID_PARTNER_FEE_RATE);

        config::assert_protocol_authority(account);
        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);

        let partner = table::borrow_mut(&mut partners.data, name);
        let old_fee_rate = partner.metadata.fee_rate;
        partner.metadata.fee_rate = new_fee_rate;
        event::emit_event(&mut partners.update_fee_rate_events, UpdateFeeRateEvent {
            name,
            old_fee_rate,
            new_fee_rate,
        });
    }

    /// Update the partner time by protocol_fee_authority
    /// Update the partner fee_rate by protocol_fee_authority
    /// Params
    ///     - name: partner name.
    ///     - start_time
    ///     - end_time
    /// Return
    ///
    public fun update_time(
        account: &signer,
        name: String,
        start_time: u64,
        end_time: u64
    ) acquires Partners {
        assert!(end_time > start_time, EINVALID_TIME);
        assert!(end_time > timestamp::now_seconds(), EINVALID_TIME);

        config::assert_protocol_authority(account);

        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);
        let partner = table::borrow_mut(&mut partners.data, name);
        partner.metadata.start_time = start_time;
        partner.metadata.end_time = end_time;
        event::emit_event(&mut partners.update_time_events, UpdateTimeEvent {
            name,
            start_time,
            end_time,
        });
    }

    /// Transfer the claim authority
    /// Params
    ///     -name
    ///     -new_receiver
    /// Return
    ///
    public fun transfer_receiver(
        account: &signer,
        name: String,
        new_receiver: address
    ) acquires Partners {
        let old_receiver_addr = signer::address_of(account);
        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);
        let partner = table::borrow_mut(&mut partners.data, name);
        assert!(old_receiver_addr == partner.metadata.receiver, EINVALID_RECEIVER);
        partner.metadata.pending_receiver = new_receiver;
        event::emit_event(&mut partners.transfer_receiver_events, TransferReceiverEvent {
            name,
            old_receiver: partner.metadata.receiver,
            new_receiver,
        })
    }

    /// Accept the partner receiver.
    /// Params
    ///     - name
    /// Return
    ///
    public fun accept_receiver(account: &signer, name: String) acquires Partners {
        let receiver_addr = signer::address_of(account);
        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);
        let partner = table::borrow_mut(&mut partners.data, name);
        assert!(receiver_addr == partner.metadata.pending_receiver, EINVALID_RECEIVER);
        partner.metadata.receiver = receiver_addr;
        partner.metadata.pending_receiver = DEFAULT_ADDRESS;
        event::emit_event(&mut partners.accept_receiver_events, AcceptReceiverEvent {
            name,
            receiver: receiver_addr
        })
    }

    /// get partner fee rate by name.
    /// Params
    ///     -name
    /// Return
    ///     -u64: ref_fee_rate
    public fun get_ref_fee_rate(name: String): u64 acquires Partners {
        let partners = &borrow_global<Partners>(@cetus_clmm).data;
        if (!table::contains(partners, name)) {
            return 0
        };
        let partner = table::borrow(partners, name);
        let current_time = timestamp::now_seconds();
        if (partner.metadata.start_time > current_time || partner.metadata.end_time <= current_time) {
            return 0
        };
        partner.metadata.fee_rate
    }

    /// Receive the coin direct from swap.
    /// Params
    ///     -name
    ///     -coin: the coin resource to transfer to partner.
    /// Return
    ///
    public fun receive_ref_fee<CoinType>(name: String, receive_coin: Coin<CoinType>) acquires Partners {
        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);

        let partner = table::borrow(&partners.data, name);

        // If partner account don't register coin, register it.
        if (!coin::is_account_registered<CoinType>(partner.metadata.partner_address)) {
            let partner_account= account::create_signer_with_capability(&partner.signer_capability);
            coin::register<CoinType>(&partner_account);
        };

        // Send ref fee to partner account.
        let amount = coin::value(&receive_coin);
        coin::deposit<CoinType>(partner.metadata.partner_address, receive_coin);

        event::emit_event(&mut partners.receive_ref_fee_events, ReceiveRefFeeEvent {
            name,
            amount,
            coin_type: type_of<CoinType>(),
        })
    }

    /// Claim partner account's ref fee for partner
    public fun claim_ref_fee<CoinType>(account: &signer, name: String) acquires Partners {
        let partners = borrow_global_mut<Partners>(@cetus_clmm);
        assert!(table::contains(&partners.data, name), EPARTNER_NOT_EXISTED);

        let partner = table::borrow(&partners.data, name);
        assert!(signer::address_of(account) == partner.metadata.receiver, EINVALID_RECEIVER);
        let balance = coin::balance<CoinType>(partner.metadata.partner_address);
        let partner_account = account::create_signer_with_capability(&partner.signer_capability);
        let ref_fee = coin::withdraw<CoinType>(&partner_account, balance);
        if (!coin::is_account_registered<CoinType>(signer::address_of(account))) {
            coin::register<CoinType>(account);
        };
        coin::deposit<CoinType>(partner.metadata.receiver, ref_fee);

        event::emit_event(&mut partners.claim_ref_fee_events, ClaimRefFeeEvent {
            name,
            receiver: partner.metadata.receiver,
            coin_type: type_of<CoinType>(),
            amount: balance,
        })
    }
}
