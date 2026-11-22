extends RefCounted
class_name StoreEntitlements
## Concessão idempotente exclusiva ao provedor de testes.
var granted_transactions: Dictionary = {}
var entitlements: Dictionary = {}
var pending_domain_payloads: Array[Dictionary] = []
func grant_simulated(transaction_id: String, product: Dictionary, wallet: Wallet) -> bool:
    if transaction_id.is_empty() or granted_transactions.has(transaction_id): return false
    granted_transactions[transaction_id] = true
    var benefits: Dictionary = product.get("benefits", {})
    if int(benefits.get("coins", 0)) > 0: wallet.add_gold(int(benefits["coins"]), &"store_simulation")
    if int(benefits.get("cash", 0)) > 0: wallet.add(int(benefits["cash"]), &"store_simulation")
    entitlements[product["id"]] = {"transaction_id": transaction_id, "benefits": benefits.duplicate(true)}
    var external := benefits.duplicate(true)
    external.erase("coins"); external.erase("cash")
    if not external.is_empty(): pending_domain_payloads.append({"product_id": product["id"], "benefits": external})
    return true
