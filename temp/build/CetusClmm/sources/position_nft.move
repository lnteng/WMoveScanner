/// The user position authority is represented by the token. User who own the token control the position.
/// Every pool has a collection, so all positions of this pool belongs to this collection.
/// The position unique index in a pool is stored in the token property map.
/// The `TOKEN_BURNABLE_BY_OWNER` is stored in every position default property_map, so the creator can burn the token when the liquidity of the position is zero.
module cetus_clmm::position_nft {
    use std::string::{Self, String};
    use std::bcs;
    use std::signer;
    use aptos_token::token;
    use cetus_clmm::utils;
    use std::vector;
    use aptos_framework::coin;

    /// Create position NFT collection
    /// Params
    ///     - creator: The creator(pool resrouce account).
    ///     - tick_spacing: The pool tick spacing.
    ///     - description: The collection description.
    ///     - uri: The NFT collection uri.
    public fun create_collection<CoinTypeA, CoinTypeB>(
        creator: &signer,
        tick_spacing: u64,
        description: String,
        uri: String
    ): String {
        let collection = collection_name<CoinTypeA, CoinTypeB>(tick_spacing);
        let mutate_setting = vector::empty<bool>();
        vector::push_back(&mut mutate_setting, true);
        vector::push_back(&mut mutate_setting, true);
        vector::push_back(&mut mutate_setting, true);
        token::create_collection(
            creator,
            collection,
            description,
            uri,
            0,
            mutate_setting
        );
        collection
    }

    /// Mint Position NFT .
    /// Params
    ///     - user: The nft receiver
    ///     - creator: The creator
    ///     - pool_index: The pool index
    ///     - position_index: The position index
    ///     - pool_uri: The pool uri
    ///     - collection: The nft collection
    /// Return
    public fun mint(
        user: &signer,
        creator: &signer,
        pool_index: u64,
        position_index: u64,
        pool_uri: String,
        collection: String,
    ) {
        let name = position_name(pool_index, position_index);
        let mutate_setting = vector<bool>[ false, false, false, false, true ];
        token::create_token_script(
            creator,
            collection,
            name,
            string::utf8(b""),
            1,
            1,
            pool_uri,
            signer::address_of(creator),
            1000000,
            0,
            mutate_setting,
            vector<String>[string::utf8(b"index"), string::utf8(b"TOKEN_BURNABLE_BY_CREATOR")],
            vector<vector<u8>>[bcs::to_bytes<u64>(&position_index), bcs::to_bytes<bool>(&true)],
            vector<String>[string::utf8(b"u64"), string::utf8(b"bool")],
        );
        // Transfer token to receivier
        token::direct_transfer_script(
            creator,
            user,
            signer::address_of(creator),
            collection,
            name,
            0,
            1
        );
    }

    /// Burn Position NFT .
    /// Params
    ///     - creator: The nft creator
    ///     - user: The nft owner
    ///     - collection_name
    ///     - pool_index: The pool index
    ///     - pos_index: The position index
    /// Return
    public fun burn(
        creator: &signer,
        user: address,
        collection_name: String,
        pool_index: u64,
        pos_index: u64,
    ) {
        token::burn_by_creator(creator, user, collection_name, position_name(pool_index, pos_index), 0, 1);
    }

    /// Generate the position nft name
    /// Params
    ///     - pool_index
    ///     - index: position index.
    /// Return
    ///     - string: position_name
    public fun position_name(
        pool_index: u64,
        index: u64
    ): String {
        let name = string::utf8(b"Cetus LP | Pool");
        string::append(&mut name, utils::str(pool_index));
        string::append_utf8(&mut name, b"-");
        string::append(&mut name, utils::str(index));
        name
    }

    /// Generate the Position Token Collection Unique Name.
    /// "Cetus Position  | tokenA-tokenB_tick(#)"
    /// Params
    ///     - tick_spacing
    /// Return
    ///     - string: collection_name
    public fun collection_name<CoinTypeA, CoinTypeB>(
        tick_spacing: u64
    ): String {
        let collect_name = string::utf8(b"Cetus Position | ");
        string::append(&mut collect_name, coin::symbol<CoinTypeA>());
        string::append_utf8(&mut collect_name, b"-");
        string::append(&mut collect_name, coin::symbol<CoinTypeB>());
        string::append_utf8(&mut collect_name, b"_tick(");
        string::append(&mut collect_name, utils::str(tick_spacing));
        string::append_utf8(&mut collect_name, b")");
        collect_name
    }

    public fun mutate_collection_uri(_creator: &signer, _collection: String, _uri: String) {
        // Not support in mainnet now
        // token::mutate_collection_uri(creator, collection, uri)
    }
}
