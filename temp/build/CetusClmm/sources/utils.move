module cetus_clmm::utils {
    use std::vector;
    use aptos_std::comparator;
    use aptos_std::type_info;
    use std::string::{Self, String};

    public fun str(num: u64): String {
        if (num == 0) {
            return string::utf8(b"0")
        };
        let remainder: u8;
        let digits = vector::empty<u8>();
        while (num > 0) {
            remainder = (num % 10 as u8);
            num = num / 10;
            vector::push_back(&mut digits, remainder + 48);
        };
        vector::reverse(&mut digits);
        string::utf8(digits)
    }

    public fun compare_coin<CoinTypeA, CoinTypeB>(): comparator::Result {
        let type_info_a = type_info::type_of<CoinTypeA>();
        let type_info_b = type_info::type_of<CoinTypeB>();
        comparator::compare<type_info::TypeInfo>(&type_info_a, &type_info_b)
    }
}