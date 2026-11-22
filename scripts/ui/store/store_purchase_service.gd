extends RefCounted
class_name StorePurchaseService
## Runtime usa indisponível; apenas testes injetam o modo simulado.
enum Mode { UNAVAILABLE, SIMULATED }
var mode := Mode.UNAVAILABLE
var online := true
var active_product: StringName = &""
var request_count := 0
func can_purchase(product_id: StringName) -> bool:
    return mode == Mode.SIMULATED and online and active_product.is_empty() and not StoreLocalization.price_for(product_id).is_empty()
func begin(product_id: StringName) -> Dictionary:
    if not online: return {"ok": false, "reason_key": "STORE_V2_OFFLINE"}
    if mode != Mode.SIMULATED: return {"ok": false, "reason_key": "STORE_V2_UNAVAILABLE"}
    if not active_product.is_empty(): return {"ok": false, "reason_key": "STORE_V2_PENDING"}
    if StoreLocalization.price_for(product_id).is_empty(): return {"ok": false, "reason_key": "STORE_V2_NO_PRICE"}
    active_product = product_id; request_count += 1
    return {"ok": true}
func complete_simulated(transaction_id: String, entitlements: StoreEntitlements, wallet: Wallet) -> Dictionary:
    if active_product.is_empty(): return {"ok": false, "reason_key": "STORE_V2_UNAVAILABLE"}
    var product_id := active_product; active_product = &""
    var applied := entitlements.grant_simulated(transaction_id, StoreCatalog.find(product_id), wallet)
    return {"ok": applied, "reason_key": "STORE_V2_PURCHASED" if applied else "STORE_V2_DUPLICATE"}
func cancel() -> void: active_product = &""
