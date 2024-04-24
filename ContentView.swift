import SwiftUI
// StoreKitをインポート
import StoreKit

// サブスクリプションの一覧を表示する画面
struct ContentView: View {
    
    @State private var products: [Product] = []
    @State private var selectedProduct: Product?
    @State private var isDetailViewPresented: Bool = false
    @ObservedObject var transactionObserver = TransactionObserver.shared
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6)
                .edgesIgnoringSafeArea(.all)
            VStack {
                HStack {
                    Spacer()
                    Text("サブスク一覧")
                        .font(.title)
                    Spacer()
                }.padding()
                List(products, id: \.id) { product in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(product.displayName)
                            Spacer()
                            if transactionObserver.purchased {
                                Text("現在のプラン")
                                    .foregroundColor(.white)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(5)
                                    .background(Color(red: 41/255, green: 178/255, blue: 255/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }   
                    }
                    .onTapGesture {
                        selectedProduct = product
                        isDetailViewPresented = true
                    }
                }
            }
            .onAppear {
                Task {
                    // サブスクリプションのプロダクトIDを指定して、プロダクト情報を取得
                    let productIdentifiers = ["com.sample.app.subscription.standard"]
                    products = try await Product.products(for: productIdentifiers)

                    // プロダクト購入のステータスを更新する
                    await transactionObserver.refreshPurchasedProducts()
                }
            }
            .sheet(isPresented: $isDetailViewPresented, content: {
                SubscriptionDetailView(product: $selectedProduct)
            })
        }
    }
}

// サブスクリプションの詳細を表示する画面
struct SubscriptionDetailView: View {
    @Binding var product: Product?
    @ObservedObject var transactionObserver = TransactionObserver.shared
    
    var body: some View {
        if let product = product {
            ZStack {
                Color(UIColor.systemGray6)
                    .edgesIgnoringSafeArea(.all)
                VStack {
                    HStack {
                        Spacer()
                        Text("プラン情報")
                            .font(.title2)
                        Spacer()
                    }
                    .padding(.vertical, 15)

                    HStack {
                        Text("プラン名")
                            .font(.subheadline)
                        Spacer()
                    }
                    
                    TextField("Planname", text: .constant(product.displayName))
                        .disabled(true)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom)

                    HStack {
                        Text("プランの説明")
                            .font(.subheadline)
                        Spacer()
                    }

                    TextEditor(text: .constant(product.description))
                        .disabled(true)
                        .frame(height: 250)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom)

                    HStack {
                        Text("価格")
                            .font(.subheadline)
                        Spacer()
                    }

                    TextField("Price", text: .constant("\(product.displayPrice)/月"))
                        .disabled(true)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom)
                    
                    if transactionObserver.purchased {
                        Button(action: {
                            Task {
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                }
                            }
                        }) {
                                Text("サブスクをキャンセルする")
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.red)
                                    .padding()
                                    .cornerRadius(50)
                            }
                        
                    } else {
                        Button(action: {
                            Task {
                                let purchaseResult = try await product.purchase()
                                switch purchaseResult {
                                    case .success(let verificationResult):
                                        switch verificationResult {
                                        case .verified(let transaction):
                                            // Give the user access to purchased content.
                                            transactionObserver.purchased = true
                                            // Complete the transaction after providing
                                            // the user access to the content.
                                            await transaction.finish()
                                        case .unverified(let transaction, let verificationError):
                                            // Handle unverified transactions based
                                            // on your business model.
                                            transactionObserver.purchased = false
                                            await transaction.finish()
                                        }
                                    case .pending:
                                        // The purchase requires action from the customer.
                                        // If the transaction completes,
                                        // it's available through Transaction.updates.
                                        transactionObserver.purchased = false
                                        break
                                    case .userCancelled:
                                        // The user canceled the purchase.
                                        transactionObserver.purchased = false
                                        break
                                    @unknown default:
                                        transactionObserver.purchased = false
                                        break
                                }
                            }
                        }) {
                            Text("サブスクを申し込む")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color(red: 41/255, green: 178/255, blue: 255/255))
                                .cornerRadius(50)
                        }
                        .padding(.top)
                    }
                }
                .padding()
            }
            .onAppear {
                Task {
                    await transactionObserver.refreshPurchasedProducts()
                }
            }
        }
    }
}

// Transactionを監視するクラス
final class TransactionObserver: ObservableObject {
    static let shared = TransactionObserver()
    var updates: Task<Void, Never>? = nil

    // 購入済みかどうかを管理するフラグ
    @Published var purchased: Bool = false
    
    init() {
        updates = newTransactionListenerTask()
    }
    
    deinit {
        // Cancel the update handling task when you deinitialize the class.
        updates?.cancel()
    }

    // トランザクションの更新を常時監視するタスク
    private func newTransactionListenerTask() -> Task<Void, Never> {
        Task(priority: .background) {
            for await verificationResult in Transaction.updates {
                self.handle(updatedTransaction: verificationResult)
            }
        }
    }
    
    // トランザクションの内容に基づき、購入済みフラグを更新する
    private func handle(updatedTransaction verificationResult: VerificationResult<StoreKit.Transaction>) {
        guard case .verified(let transaction) = verificationResult else {
            // Ignore unverified transactions.
            purchased = false
            return
        }

        // トランザクション取消日が入っている場合、購入済みフラグをfalseにする
        if let revocationDate = transaction.revocationDate {
            // Remove access to the product identified by transaction.productID.
            // Transaction.revocationReason provides details about
            // the revoked transaction.
            purchased = false
            return
        // トランザクションの有効期限が切れている場合、購入済みフラグをfalseにする
        } else if let expirationDate = transaction.expirationDate,
            expirationDate < Date() {
            // Do nothing, this subscription is expired.
            purchased = false
            return
        // トランザクションがアップグレードされている場合、購入済みフラグをtrueにする
        } else if transaction.isUpgraded {
            // Do nothing, there is an active transaction
            // for a higher level of service.
            purchased = true
            return
        // そのほか。トランザクションが有効な場合、購入済みフラグをtrueにする
        } else {
            // Provide access to the product identified by
            // transaction.productID.
            purchased = true
            return
        }
    }

    // ユーザーが権利を持つプロダクトの最新のトランザクション情報を取得し、購入済みフラグを更新する
    func refreshPurchasedProducts() async {
        // Iterate through the user's purchased products.
        for await verificationResult in Transaction.currentEntitlements {
            switch verificationResult {
            case .verified(let transaction):
                // Check the type of product for the transaction
                // and provide access to the content as appropriate.
                purchased = true
                return
            case .unverified(let unverifiedTransaction, let verificationError):
                // Handle unverified transactions based on your
                // business model.
                purchased = false
                return
            }
        }
    }
}
