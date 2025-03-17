/*
/// Module: market
module market::market;
*/

module market::market {
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap, PurchaseCap};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{TxContext, sender};
    use sui::coin::{Coin};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field;
    use sui::clock::{Self, Clock};
    use std::string::{String};
    use std::vector;
    use std::option::{Self, Option};

    // ========== 错误码 ==========
    const ENOT_AUTHORIZED: u64 = 0;
    const EINVALID_USER_TYPE: u64 = 1;
    const EINSUFFICIENT_DEPOSIT: u64 = 2;
    const EREPORT_EXISTS: u64 = 3;
    const ENOT_RENTER: u64 = 4;
    const EINSUFFICIENT_FUNDS: u64 = 5;
    const EInvalidDuration: u64 = 6;
    const ERentNotExpired: u64 = 7;
    const ENOT_FOR_SALE: u64 = 8;
    const EINSUFFICIENT_PAYMENT: u64 = 9;
    const EALREADY_LISTED: u64 = 10;

    // ========== 数据结构 ==========
    struct SaleListing has key, store {
        id: UID,
        sale_price: u64,
        fee_rate: u64 // 费率（基于万分比，如 250 表示 2.5%）
    }

    struct PurchaseReceipt has key, store {
        id: UID,
        parking_lot_id: ID,
        buyer: address,
        purchase_time: u64
    }

    struct ListingEvent has copy, drop {
        kiosk_id: ID,
        item_id: ID,
        price: u64,
        fee_rate: u64
    }

    struct PriceUpdateEvent has copy, drop {
        kiosk_id: ID,
        new_price: u64
    }
    

    struct RentPolicy has key, store {
        id: UID,
        price_per_sec: u64,
        min_duration: u64,
        deposit_amount: u64
    }

    struct RentReceipt has key, store {
        id: UID,
        parking_lot_id: ID,
        renter: address,
        start_time: u64,
        end_time: u64,
        deposit: Balance<SUI>
    }

    struct UserType has copy, drop {
        is_admin: bool,
        level: u8 // 0=C,1=B,2=A
    }

    struct User has key, store {
        id: UID,
        user_type: UserType,
        parking_lots: vector<ID>,
        kiosk: Option<Kiosk>
    }

    struct ParkingLot has key, store {
        id: UID,
        location: String,
        current_renter: Option<address>,
        is_listed: bool,
        sale_price: u64,
        fee_rate: u64
    }

    struct RentalInfo has store {
        renter: address,
        deposit: Balance<SUI>,
        rent_end_time: u64
    }

    struct Report has key, store {
        id: UID,
        parking_lot_id: ID,
        reporter: address,
        is_verified: bool
    }

    struct AdminCap has key { id: UID }

    // ========== 初始化模块 ==========
    fun init(ctx: &mut TxContext) {
        // 创建管理员用户
        let (admin_kiosk, admin_cap) = kiosk::default();
        let admin_user = User {
            id: object::new(ctx),
            user_type: UserType { is_admin: true, level: 2 },
            parking_lots: vector::empty(),
            kiosk: option::some(admin_kiosk)
        };
        transfer::public_transfer(admin_user, sender(ctx));
        transfer::public_transfer(admin_cap, sender(ctx));

        // 创建管理员能力标记
        let admin_cap_marker = AdminCap { id: object::new(ctx) };
        transfer::public_transfer(admin_cap_marker, sender(ctx));
    }

    // ========== 用户管理 ==========
    public entry fun create_user(ctx: &mut TxContext) {
        let (user_kiosk, user_cap) = kiosk::default();
        let user = User {
            id: object::new(ctx),
            user_type: UserType { is_admin: false, level: 0 },
            parking_lots: vector::empty(),
            kiosk: option::some(user_kiosk)
        };
        transfer::public_transfer(user, sender(ctx));
        transfer::public_transfer(user_cap, sender(ctx));
    }

    fun upgrade_user(user: &mut User) {
        if (user.user_type.level == 0) {
            user.user_type.level = 1;
        }
    }

    // ========== 停车场管理 ==========
    public entry fun create_parking_lot(
        user: &mut User,
        location: String,
	    sale_price: u64,
        fee_rate: u64,
        ctx: &mut TxContext
    ) {

        let parking_lot = ParkingLot {
            id: object::new(ctx),
            location,
            current_renter: option::none(),
            is_listed: false,
            sale_price,
            fee_rate
        };

        // 存入用户Kiosk
        let kiosk = option::borrow_mut(&mut user.kiosk);
        kiosk::place(kiosk, parking_lot);
        vector::push_back(&mut user.parking_lots, object::id(&parking_lot));
        upgrade_user(user);
    }

    // ========== 租赁核心逻辑 ==========
    /// 初始化租赁策略
    public entry fun create_policy(
        price_per_sec: u64,
        min_duration: u64,
        deposit_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(user.user_type.level >= 1, EINVALID_USER_TYPE);
        let policy = RentPolicy {
            id: object::new(ctx),
            price_per_sec,
            min_duration,
            deposit_amount
        };
        transfer::transfer(policy, tx_context::sender(ctx));
    }

    public entry fun list_for_rent(
        user: &User,
        parking_lot: ParkingLot,
        policy: &RentPolicy, 
        ctx: &mut TxContext
    ) {
        assert!(user.user_type.level >= 1, EINVALID_USER_TYPE);

        kiosk::place(kiosk, parking_lot);
        let policy_obj = RentPolicy {
            id: object::new(ctx),
            price_per_sec: policy.price_per_sec,
            min_duration: policy.min_duration,
            deposit_amount: policy.deposit_amount
        };
        kiosk::add_policy(kiosk, policy_obj);
    }

    public entry fun rent_parking(
        user: &mut User,
        kiosk: &mut Kiosk,
        clock: &Clock,
        duration: u64,
        payment: Coin<SUI>,
        deposit: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        
        // 获取租赁策略
        let policy = kiosk::borrow_policy<RentPolicy>(kiosk);
        
        // 验证租赁时长
        assert!(duration >= policy.min_duration, EInvalidDuration);
        
        // 计算总费用
        let total_cost = policy.price_per_sec * duration;
        assert!(coin::value(&payment) >= total_cost, EINSUFFICIENT_FUNDS);
        assert!(coin::value(&deposit) >= policy.deposit_amount, EINSUFFICIENT_DEPOSIT);

        // 创建租赁凭证
        let receipt = RentReceipt {
            id: object::new(ctx),
            parking_lot_id: kiosk::item_id(kiosk),
            renter: sender(ctx),
            start_time: clock::timestamp_ms(clock),
            end_time: clock::timestamp_ms(clock) + (duration * 1000),
            deposit: coin::into_balance(deposit)
        };

        // 处理支付
        let payment_balance = coin::into_balance(payment);
        kiosk::deposit_balance(kiosk, payment_balance);

        // 锁定停车场NFT
        kiosk::lock_item(kiosk, receipt);
    }

    public entry fun return_parking(
        user: &User,
        kiosk: &mut Kiosk,
        receipt: RentReceipt,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // 验证租赁时间
        assert!(clock::timestamp_ms(clock) >= receipt.end_time, ERentNotExpired);
        
        // 退还押金
        let deposit_coin = coin::from_balance(receipt.deposit, ctx);
        transfer::public_transfer(deposit_coin, receipt.renter);

        // 取回停车场NFT
        let parking_lot = kiosk::take_item<ParkingLot>(kiosk);
        parking_lot.is_listed = false;
        parking_lot.current_renter = option::none();

        // 返回给所有者
        kiosk::place(kiosk, parking_lot);
        object::delete(receipt);
    }

    // ========== 自动回收逻辑 ==========
    public entry fun reclaim_overdue(
        owner_cap: &KioskOwnerCap,
        receipt: RentReceipt,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(clock::timestamp_ms(clock) > receipt.end_time, ERentNotExpired);
        
        // 没收押金
        let deposit_coin = coin::from_balance(receipt.deposit, ctx);
        transfer::public_transfer(deposit_coin, sender(ctx));

        // 强制取回停车场
        let parking_lot = kiosk::take_item_with_cap<ParkingLot>(owner_cap);
        parking_lot.is_listed = false;
        parking_lot.current_renter = option::none();
        kiosk::place_with_cap(owner_cap, parking_lot);
        object::delete(receipt);
    }

   // ========== 租赁功能结束 ========

    // ========== 购买功能 ========== 

    /// 上架停车场出售
    public entry fun list_for_sale(
        kiosk: &mut Kiosk,
        owner_cap: &KioskOwnerCap,
        parking_lot: ParkingLot,
        price: u64,
        fee_rate: u64,
        ctx: &mut TxContext
    ) {
        // 验证上架权限
        assert!(kiosk::is_owner(owner_cap, kiosk), ENotOwner);
        assert!(!parking_lot.is_listed, EALREADY_LISTED);
        
        // 更新停车场状态
        parking_lot.is_listed = true;

        // 创建销售清单
        let listing = SaleListing {
            id: object::new(ctx),
            price,
            fee_rate
        };

        // 将停车场放入Kiosk并关联销售信息
        kiosk::place(kiosk, parking_lot);
        kiosk::add_policy(kiosk, listing);

        // 发出上架事件
        event::emit(ListingEvent {
            kiosk_id: object::id(kiosk),
            item_id: object::id(&parking_lot),
            price,
            fee_rate
        });
    }

    /// 购买停车场
    public entry fun purchase(
        user: &mut User,
        kiosk: &mut Kiosk,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // 获取销售策略
        let listing: &SaleListing = kiosk::borrow_policy<SaleListing>(kiosk);

        // 验证支付金额
        assert!(coin::value(&payment) >= listing.price, EInsufficientPayment);

        // 执行购买
        let (parking_lot, purchase_cap) = kiosk::purchase(kiosk, payment);

        // 计算分成
        let total = coin::value(&payment);
        let fee = total * listing.fee_rate / 10000;
        let to_owner = total - fee;

        // 资金分配
        let payment_balance = coin::into_balance(payment);
        let (owner_balance, fee_balance) = balance::split(payment_balance, to_owner);
        
        // 转账款给原所有者
        transfer::public_transfer(
            coin::from_balance(owner_balance, ctx),
            kiosk::owner(kiosk)
        );

        // 平台手续费处理
        transfer::public_transfer(
            coin::from_balance(fee_balance, ctx),
            @platform_address
        );

        // 转移停车场所有权
        transfer::public_transfer(parking_lot, sender(ctx));
        object::delete(purchase_cap);
        upgrade_user(user);
    }

    /// 修改挂牌价格
    public entry fun update_price(
        kiosk: &mut Kiosk,
        owner_cap: &KioskOwnerCap,
        new_price: u64
    ) {
        assert!(kiosk::is_owner(owner_cap, kiosk), ENotOwner);
        
        let listing: &mut SaleListing = kiosk::borrow_policy_mut(kiosk);
        listing.price = new_price;

        event::emit(PriceUpdateEvent {
            kiosk_id: object::id(kiosk),
            new_price
        });
    }

    /// 下架停车场
    public entry fun delist(
        kiosk: &mut Kiosk,
        owner_cap: &KioskOwnerCap,
        ctx: &mut TxContext
    ) {
        assert!(kiosk::is_owner(owner_cap, kiosk), ENotOwner);

        // 取回停车场
        let parking_lot = kiosk::take(kiosk, ParkingLot);
        
        // 移除销售策略
        let listing = kiosk::remove_policy<SaleListing>(kiosk);
        object::delete(listing);

        // 返还给所有者
        transfer::public_transfer(parking_lot, sender(ctx));
    }

}