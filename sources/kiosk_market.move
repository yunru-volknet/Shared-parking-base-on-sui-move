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

    //3.12������־������
    //Ŀǰ���뷨���� RentalVoucher ���������balance�ֶ�����pool�������Ļ�delistʱҪ˳���capҲ��ɾ��
    //pool��cap���½���ʽ��ȫ����kiosk��new
    //3.13������־��Ŀǰ�����Ѿ��������ƣ���ȱ�ٴ����벹���rent��ع��ܵĸ���ܺ�Voucher������
    //Voucher�����ܲ���kiosk

    //����
    const MIN_TIME: u64 = 3_600_000_000;
    
    // ========== ������ ==========
    
    // ========== ���ݽṹ ==========
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
    }//��Ҫlist������list_for_rent����

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

    // ========== ��ʼ��ģ�� ==========
    //v
    fun init(ctx: &mut TxContext) {
        // ��������Ա�û�
        let (admin_kiosk, admin_cap) = kiosk::default(ctx);
        let admin_user = User {
            id: object::new(ctx),
            user_type: UserType { is_admin: true, level: 1 },
            parking_lots: vector::empty(),
            kiosk: option::some(admin_kiosk)
        };
        transfer::public_transfer(admin_user, sender(ctx));

        // ��������Ա�������
        let admin_cap_marker = AdminCap { id: object::new(ctx) };
        transfer::public_transfer(admin_cap_marker, sender(ctx));
    }

    // ========== �û����� ==========
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
    //���ܹ����ĺ���
    //v
    fun upgrade_user(user: &mut User) {
        if (user.user_type.level == 0) {
            user.user_type.level = 1;
        }
    }

    // ========== ͣ�������� ==========
    //ȱ�ٵ�λʱ������
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
    // ========== ���޺����߼� ==========
    //v
    public fun list_for_rent(
        parking: &ParkingLot
    ){
        assert!(user.user_type.level == 1, EINVALID_USER_TYPE)
        assert!()//ȷ�����ڲ����ڳ���״̬
        let parking_lot_id = parking.id;
        let voucher = RentalVoucher {
            id: object::new(ctx),
            owner: sender(ctx),
            parking_lot_id,
            renter: @0x0,    // ��ʼֵ��ʾδ����
            stop_time: 0,     // ��ʼʱ��δ����
            is_using: false
        };

        let cap = Cap {
            id: object::new(ctx),
            for: object::id(&voucher) ,
        };
        
        // �ؼ�������������Ϊ����״̬
        transfer::share_object(voucher);
        sui::transfer::transfer(cap, ctx.sender());
    }//����һ��public����Ʊ��

    //ȱ�ٸ�������߼���
    public fun rent(
        unit_count: u64,
        parkinglot: &ParkingLot, 
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        assert!()//����״̬
        assert!()//parkinglot.id == voucher.parking_lot_id
        // ����������ʱ��
        let total_duration_ms = (MIN_TIME * unit_count);
        
        // �����ֹʱ��
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
    }//���ã��޸�Ʊ���ֶ�

    //ȱ���޸�parkinglot�ֶε��߼��ͻؿ��߼�
    public fun stop_rent(
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        assert!()//�����֤
        assert!()//��is_using�ֶο��Ƿ�����ʹ����
        rentalvoucher.renter = @0x0;
        rentalvoucher.stop_time = 0;
    }
    public fun delist_for_rent(){
        // ״̬��֤
        assert!( rental_record.renter == @0x0 || clock::timestamp_ms(clock) > rental_record.stop_time, ECannotDelete);
            // ���ٶ���
        let RentalVoucher { 
            id, 
            owner: _, 
            parking_lot_id: _, 
            renter: _, 
            stop_time: _, 
            is_using: _, 
            balance 
        } = voucher; // �⹹ RentalVoucher�������޹��ֶ�
        balance::destroy_zero(balance); // ���� balance
        object::delete(id); // ɾ�� RentalVoucher ����

        let Cap { id, for: _ } = cap; // �⹹ cap������ `for` �ֶ�
        object::delete(id);           // ɾ�� cap ����

    }//ֹͣ����
    //�ѹ���Ʊ�ݵ�isrent��Ϊ1���޸�renter����Ϣ��ע�⣺�����û�з���kiosk�ĸ���

    // ========== ��������߼� ==========
    public fun list_sell(
        kiosk: &mut Kiosk,
        owner_cap: &KioskOwnerCap,
        nft_id: UID,
        price: u64,
        ctx: &mut TxContext
    ){
        assert!(user.user_type.level == 1, EINVALID_USER_TYPE)
        assert!()//���Ƿ��ڳ���״̬��Ӧ�ò����ڲ��ܳ���
        Kiosk::list(kiosk, owner_cap, nft_id, price, ctx)
    }
    public fun purchase(
        kiosk: &mut Kiosk,
        nft_id: UID,
        payment: Coin<Balance>,
        ctx: &mut TxContext
    ){
        // ��ȡ Listing
        let price = Kiosk::get_price(kiosk, nft_id);

        // ���֧�����
        assert!(coin::value(&payment) >= price, E_INSUFFICIENT_FUNDS);

        // ���� NFT
        let nft = Kiosk::purchase(kiosk, nft_id, ctx);

        // ���㷵�ظ����
        if coin::value(&payment) > price {
            let change = coin::split(&mut payment, coin::value(&payment) - price);
            transfer::transfer(change, tx_context::sender(ctx));
        }

        // ֧��ת������
        let seller = Kiosk::get_seller(kiosk, nft_id);
        transfer::transfer(payment, seller);

        // �� NFT ת�����
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

    // ========== ʹ��ͣ���� ==========
    public fun owner_use(
        parkinglot: &mut ParkingLot
    ){
        assert!()//����Ƿ�Ϊ������
        assert!()//���Ƿ���ʹ����

        //�޸��ֶ�using
        parkinglot.is_using = true; 
    }//���Ƿ��ѳ��⣬�鿴Ʊ��
    public fun owner_use_stop(
        parkinglot: &mut ParkingLot
    ){
        assert!(user.user_type.level == 1, EINVALID_USER_TYPE)
        
        //�޸��ֶ�using
        parkinglot.is_using = false;
    }
    public fun not_owner_use(
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        assert!()//���վݵ�id_for��ͣ����id�Ƿ���ͬ
        assert!()//���Ƿ��ڿ���ʱ����
        assert!(rentalvoucher.is_using == false , 1001)//���Ƿ���ʹ����
        
        //�޸��ֶ�using
        rentalvoucher.is_using = true;
    }
    public fun not_owner_use_stop(
        rentalvoucher: &mut RentalVoucher,
        ctx: &mut TxContext
    ){
        //�޸��ֶ�using
        rentalvoucher.is_using = false;
    }
}