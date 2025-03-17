/*
/// Module: kiosk_market
module kiosk_market::kiosk_market;
*/

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions

module kiosk_market::kiosk_market {
    use sui::kiosk;
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{TxContext, sender};
    use sui::coin::{Coin};
    use sui::coin::SUI;
    use sui::balance::{Self, Balance};
    use sui::dynamic_field;
    use sui::clock::{Self, Clock};
    use std::string::{String};
    use std::vector;
    use std::option::{Self, Option};

    //3.12开发日志，结束
    //目前的想法是在 RentalVoucher 对象上添加balance字段做成pool，这样的话delist时要顺便把cap也给删掉
    //pool和cap的新建方式完全参照kiosk的new
    //3.13开发日志，目前功能已经基本完善，仅缺少错误码补充和rent相关功能的付款功能和Voucher的提款功能
    //Voucher的提款功能参照kiosk

    //常量
    const MIN_TIME: u64 = 3_600_000_000;
    
    // ========== 错误码 ==========
    
    // ========== 数据结构 ==========
    public struct UserType has copy, drop, store { 
        is_admin: bool,
        level: bool
    }

    public struct User has key, store {
        id: UID,
        user_type: UserType,
        parking_lots: vector<ID>,
        kiosk: Option<Kiosk>
    }

    public struct ParkingLot has key, store {
        id: UID,
        location: String,
        is_using: bool,
        is_listed: bool,
        is_listed_for_rent: bool,
        rent_price: u64,
        fee_rate: u64
    }//需要list参数，list_for_rent参数

    public struct RentalVoucher has key, store {
        id: UID,
        owner: address,
        parking_lot_id: ID,
        renter: address,
        stop_time: u64,
        is_using:bool,
        balance: Balance<SUI>
    }

    struct Cap has key, store {
        id: UID,
        for: UID
    }

    public struct AdminCap has key { id: UID }

    // ========== 初始化模块 ==========
    //v
    fun init(ctx: &mut TxContext) {
        // 创建管理员用户
        let (admin_kiosk, admin_cap) = kiosk::default(ctx);
        let admin_user = User {
            id: object::new(ctx),
            user_type: UserType { is_admin: true, level: 1 },
            parking_lots: vector::empty(),
            kiosk: option::some(admin_kiosk)
        };
        transfer::public_transfer(admin_user, sender(ctx));

        // 创建管理员能力标记
        let admin_cap_marker = AdminCap { id: object::new(ctx) };
        transfer::public_transfer(admin_cap_marker, sender(ctx));
    }

    // ========== 用户管理 ==========
    //v
    public entry fun create_user(ctx: &mut TxContext){
        let (user_kiosk, user_cap) = kiosk::default();
        let user = User {
            id: object::new(ctx),
            user_type: UserType { is_admin: false, level: 0 },
            parking_lots: vector::empty(),
            kiosk: option::some(user_kiosk)
        };
        transfer::public_transfer(user, sender(ctx));      
    }
    //不能公开的函数
    //v
    fun upgrade_user(user: &mut User) {
        if (user.user_type.level == 0) {
            user.user_type.level = 1;
        }
    }

    // ========== 停车场管理 ==========
    //缺少单位时间设置
    public entry fun create_parking_lot(
        user: &mut User,
        location: String,
	    sale_price: u64,
        fee_rate: u64,
        ctx: &mut TxContext
    ){
        let parking_lot = ParkingLot {
            id: object::new(ctx),
            location,
            is_using: false,
            is_listed: false,
            is_listed_for_rent: false,
            sale_price,
            fee_rate
        };

        upgrade_user(user);
    }
    // ========== 租赁核心逻辑 ==========
    //v
    public fun list_for_rent(
        parking: &ParkingLot
    ){
        assert!(user.user_type.level == 1, EINVALID_USER_TYPE)
        assert!()//确保现在不处于出租状态
        let parking_lot_id = parking.id;
        let voucher = RentalVoucher {
            id: object::new(ctx),
            owner: sender(ctx),
            parking_lot_id,
            renter: @0x0,    // 初始值表示未分配
            stop_time: 0,     // 初始时间未设置
            is_using: false
        };

        let cap = Cap {
            id: object::new(ctx),
            for: object::id(&voucher) ,
        };
        
        // 关键：将对象设置为共享状态
        transfer::share_object(voucher);
        sui::transfer::transfer(cap, ctx.sender());
    }//设置一个public租用票据

    //缺少付款相关逻辑和
    public fun rent(
        unit_count: u64,
        parkinglot: &ParkingLot, 
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        assert!()//闲置状态
        assert!()//parkinglot.id == voucher.parking_lot_id
        // 计算总租赁时间
        let total_duration_ms = (MIN_TIME * unit_count);
        
        // 计算截止时间
        let stop_time = clock::timestamp_ms(clock) + total_duration_ms;

        let parking_lot_id = object::id(&parking_lot);
        let voucher = RentalVoucher {
            id,
            owner,
            parking_lot_id,
            renter: sender(ctx),
            stop_time,
            is_using,
            balance: balance::zero()
        };
    }//租用，修改票据字段

    //缺少修改parkinglot字段的逻辑和回款逻辑
    public fun stop_rent(
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        assert!()//身份验证
        assert!()//查is_using字段看是否正在使用中
        rentalvoucher.renter = @0x0;
        rentalvoucher.stop_time = 0;
    }
    public fun delist_for_rent(){
        // 状态验证
        assert!( rental_record.renter == @0x0 || clock::timestamp_ms(clock) > rental_record.stop_time, ECannotDelete);
            // 销毁对象
        let RentalVoucher { 
            id, 
            owner: _, 
            parking_lot_id: _, 
            renter: _, 
            stop_time: _, 
            is_using: _, 
            balance 
        } = voucher; // 解构 RentalVoucher，忽略无关字段
        balance::destroy_zero(balance); // 销毁 balance
        object::delete(id); // 删除 RentalVoucher 对象

        let Cap { id, for: _ } = cap; // 解构 cap，忽略 `for` 字段
        object::delete(id);           // 删除 cap 对象

    }//停止出租
    //把公开票据的isrent改为1并修改renter的信息，注意：仅针对没有放上kiosk的个体

    // ========== 购买核心逻辑 ==========
    public fun list_sell(
        kiosk: &mut Kiosk,
        owner_cap: &KioskOwnerCap,
        nft_id: UID,
        price: u64,
        ctx: &mut TxContext
    ){
        assert!(user.user_type.level == 1, EINVALID_USER_TYPE)
        assert!()//查是否处于出租状态，应该不处于才能出售
        Kiosk::list(kiosk, owner_cap, nft_id, price, ctx)
    }
    public fun purchase(
        kiosk: &mut Kiosk,
        nft_id: UID,
        payment: Coin<Balance>,
        ctx: &mut TxContext
    ){
        // 获取 Listing
        let price = Kiosk::get_price(kiosk, nft_id);

        // 检查支付金额
        assert!(coin::value(&payment) >= price, E_INSUFFICIENT_FUNDS);

        // 购买 NFT
        let nft = Kiosk::purchase(kiosk, nft_id, ctx);

        // 找零返回给买家
        if coin::value(&payment) > price {
            let change = coin::split(&mut payment, coin::value(&payment) - price);
            transfer::transfer(change, tx_context::sender(ctx));
        }

        // 支付转给卖家
        let seller = Kiosk::get_seller(kiosk, nft_id);
        transfer::transfer(payment, seller);

        // 将 NFT 转给买家
        transfer::transfer(nft, tx_context::sender(ctx));
    }

    public fun delist_and_take(
        kiosk: &mut Kiosk,
        owner_cap: &KioskOwnerCap,
        nft_id: UID,
        ctx: &mut TxContext
    ){
        Kiosk::delist(kiosk, owner_cap, nft_id, ctx);
        Kiosk::take(kiosk, owner_cap, nft_id, ctx);
    }

    // ========== 使用停车场 ==========
    public fun owner_use(
        parkinglot: &mut ParkingLot
    ){
        assert!()//检查是否为所有人
        assert!()//查是否在使用中

        //修改字段using
        parkinglot.is_using = true; 
    }//查是否已出租，查看票据
    public fun owner_use_stop(
        parkinglot: &mut ParkingLot
    ){
        assert!(user.user_type.level == 1, EINVALID_USER_TYPE)
        
        //修改字段using
        parkinglot.is_using = false;
    }
    public fun not_owner_use(
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        assert!()//查收据的id_for和停车场id是否相同
        assert!()//查是否在可用时间内
        assert!(rentalvoucher.is_using == false , 1001)//查是否在使用中
        
        //修改字段using
        rentalvoucher.is_using = true;
    }
    public fun not_owner_use_stop(
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        //修改字段using
        rentalvoucher.is_using = false;
    }
}