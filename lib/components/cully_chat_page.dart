import '../services/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/trade_republic_widgets.dart';
import '../services/cultioo_spinner.dart';

class CullyChatPage extends StatefulWidget {
  final bool isDark;
  final Function(String)? onLanguageChanged;

  const CullyChatPage({
    super.key,
    required this.isDark,
    this.onLanguageChanged,
  });

  @override
  State<CullyChatPage> createState() => _CullyChatPageState();
}

class _CullyChatPageState extends State<CullyChatPage>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _isTyping = false;
  late AnimationController _typingAnimationController;
  late AnimationController _appearanceAnimationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Cultioo Knowledge Base for AI context - Professional Business Intelligence
  static const String _cultiooContext = """
ROLE: You are "Cully", the official AI Business Assistant for Cultioo. Your job is to support CEOs and Purchasing Managers in managing their agricultural logistics.

===== COMPANY PROFILE =====
Name: Cultioo
Legal Form: C-Corporation (Delaware)
Sector: Agricultural Logistics Technology (USA)
Core Mission: Providing liquidity and transportation solutions for the US agricultural sector through digital processing and credit models.

===== FINANCIAL MODEL & PAYMENT TERMS =====
Payment Structure: Net 30 / Net 60 (payment terms of 30 or 60 days for buyers)
Driver Payout: Drivers are paid within **14 days** after successful delivery
Late Fee (THE 15% RULE): When payment terms are exceeded (from day 31 or 61), an automatic fee of **15%** on the invoice amount is applied. This is non-negotiable as it ensures our drivers remain compensated.
Payment Processing: Via virtual accounts created individually for each user through Stripe.

===== CREDIT & SECURITY LOGIC =====
Standard Limit: New companies typically start with a credit limit of **\$75,000**
Credit Check: Limits are validated based on data from Middesk and Dun & Bradstreet (D&B)
Insurance: All cargo is insured (details per Terms of Service/AGB). Damages must be reported within **24 hours** with photo evidence via the app.

===== ROLES & PERMISSIONS =====
Company Admin (The Boss): Must approve every order created by employees in the app (Approval Workflow)
Buyer/Purchaser: Can create orders but has no independent budget without admin approval

===== CORPORATE STRUCTURE =====
Authorized Shares: 10,000,000 shares
Par Value: \$0.00001
Tax ID: EIN (applied via Stripe Atlas / IRS)

===== STRIPE INTEGRATION =====
All payments are processed through secure, virtual Stripe accounts assigned to each user.
Payment methods: Credit Card, SEPA Direct Debit, ACH, Wire Transfer.

===== PRODUCT CATEGORIES =====
- Fruits & Vegetables
- Dairy Products & Eggs
- Meat & Sausages
- Bakery Products
- Jams & Spreads
- Honey & Sweets
- Beverages
- Grains & Legumes
- Nuts & Dried Fruits
- Herbs & Spices
- And many more agricultural products...

===== CONTACT & SUPPORT =====
Email: support@cultioo.com
Website: www.cultioo.com
App: Available for iOS and Android

===== IMPORTANT RULES FOR YOUR RESPONSES =====
1. FACT-CHECK: Always reference the 15% late fee from day 31, the 14-day driver payout, and the \$75k starting limit.
2. PROFESSIONALISM: Answer briefly, precisely, and business-oriented.
3. DATA PRIVACY: Never reveal internal passwords or API keys (e.g., Stripe/Mailgun).
4. ESCALATION: If a user asks for legal details not covered in the basic Terms of Service, refer them to support@cultioo.com.
5. CONTEXT: Use the provided user data (limit, open invoices) to deliver personalized assistance.
6. DISPUTES: If a user complains about the 15% fee, explain that this allows Cultioo to provide the liquidity that keeps the agricultural supply chain moving.

===== RESPONSE FORMATTING =====
- Use bolding for numbers and deadlines (e.g., **\$75,000**, **15%**, **14 days**)
- Use bullet points for lists of invoices or orders
- Keep responses under 4 sentences unless explaining a complex process
- Be concise but thorough

===== FREQUENTLY ASKED QUESTIONS =====
- Why can't I place an order? → Check credit limit utilization and overdue invoices.
- What is the 15% fee? → Automatic late fee applied on day 31 of overdue payment.
- How do I increase my credit limit? → Contact support for a credit review based on payment history.
- How do I approve orders? → Company Admins can approve in the Orders section.
- What payment methods are available? → Credit Card, SEPA, ACH, Wire Transfer via Stripe.
- When do drivers get paid? → Within 14 days after successful delivery.

===== TERMS OF SERVICE (TOS) SUMMARY =====
Effective Date: January 1, 2026 | Version 1.0

**1. Cultioo's Role:**
- Cultioo is a TECHNOLOGY PLATFORM only (marketplace intermediary)
- NOT a reseller, agent, broker, or manufacturer
- NOT a party to purchase contracts between buyer and seller
- The SELLER is the "Seller of Record" responsible for product quality, legality, and warranties

**2. Account & User Obligations:**
- Users must be 18+ years old
- Provide true, accurate, and complete information
- User is responsible for account security and all activities
- Cultioo can suspend/terminate accounts for TOS violations, fraud, or non-payment

**3. Product Liability:**
- Products sold "AS-IS" by sellers
- Cultioo makes NO warranties about products
- Seller is solely liable for product quality, safety, descriptions, and compliance with FDA/USDA/CPSC
- Buyer must inspect products upon delivery

**4. Payment Terms (via Stripe Connect):**
- All payments processed through Stripe
- Users must accept Stripe Terms (https://stripe.com/legal/connect-account)
- Commissions automatically deducted from transactions
- Sellers must provide W-9 (US) or W-8BEN (non-US) for IRS reporting
- Form 1099-K issued for transactions over \$600/year
- Backup withholding (24%) applied if no valid TIN provided

**5. Logistics & Delivery:**
- Risk transfers at handover to carrier (FOB Origin)
- Delvioo Drivers are INDEPENDENT CONTRACTORS (not employees)
- Driver liable for damages during transport
- Seller liable for self-organized shipping

**6. Reporting Issues:**
- **30-DAY REPORTING PERIOD** from delivery date
- Problems must be reported within 30 days via the app
- After 30 days, issues cannot be claimed via the platform
- Primary dispute resolution between buyer and seller directly

**7. Liability & Legal:**
- Cultioo NOT liable for indirect, consequential, or punitive damages
- Maximum liability capped at: fees paid in last 6 months OR \$100 (whichever is greater)
- Users must INDEMNIFY Cultioo from all claims
- **BINDING ARBITRATION** required (AAA Commercial Rules)
- **CLASS ACTION WAIVER** - no class lawsuits allowed
- Opt-out of arbitration within 30 days of first use
- Governed by Delaware law

**8. Privacy & Data:**
- Data processed for transactions, compliance (KYC/AML), fraud prevention
- Seller info disclosed to buyers (INFORM Consumers Act compliance)
- Data shared with Stripe, authorities (IRS, law enforcement)

**9. Termination:**
- Users can terminate anytime
- Cultioo can terminate for TOS violations
- Outstanding payouts withheld until claims resolved

**10. Contact for TOS Questions:**
- General: support@cultioo.com
- Legal: legal@cultioo.com
- Disputes: disputes@cultioo.com

IMPORTANT: For full legal details, users should read the complete TOS at www.cultioo.com or contact legal@cultioo.com.

===== PRIVACY POLICY SUMMARY =====
Effective Date: January 1, 2026 | Version 1.0

**1. Data Controller:**
- Cultioo Inc., Delaware Corporation
- Privacy contact: privacy@cultioo.com

**2. Legal Compliance:**
- FTC Act (fair data practices)
- California CCPA/CPRA
- Virginia VCDPA, Colorado CPA, Connecticut CTDPA, Utah UCPA
- Other applicable state privacy laws

**3. Data Categories Collected:**
- **Identifiers**: Name, email, address, phone, device ID, IP address
- **Commercial Info**: Purchase history, transaction records, payment method (last 4 digits only)
- **Network Activity**: App interaction, session data, device/OS details
- **Sensitive Personal Info (SPI)**: Precise location (LOCAL ONLY), financial info (Stripe), message contents

**4. Data Security (Technical Measures):**
- Passwords: Irreversible hashing (bcrypt/Argon2) - NO plain text storage
- Encryption: All transmissions via HTTPS/TLS
- Access Control: Only authorized employees with legitimate business need
- Account Deletion: Final and irrevocable - NO recovery possible

**5. Location Data - PRIVACY BY DESIGN:**
⚠️ IMPORTANT: Location stored ONLY on user's device
- NEVER transmitted to Cultioo servers
- NEVER shared with third parties
- User has complete control via device settings

**6. Payment Processing (Stripe):**
- ALL payment data processed by Stripe Inc. (PCI-DSS Level 1 certified)
- Cultioo stores ONLY last 4 digits
- Stripe is INDEPENDENT controller with separate privacy policy
- Stripe Privacy: https://stripe.com/privacy

**7. Data Sharing:**
- NO sharing for advertising or marketing purposes
- Shared with Service Providers only:
  • Delvioo (delivery): address, name, phone (emergency only)
  • Stripe (payments): payment data, transaction details
  • IT/Infrastructure providers (hosting, analytics)
- Legal disclosure: Law enforcement (court orders), IRS (tax requirements)

**8. Sale/Sharing of Data:**
- Cultioo does NOT SELL personal information
- Cultioo does NOT SHARE for cross-context behavioral advertising
- Global Privacy Control (GPC) signals will be honored

**9. User Privacy Rights (CCPA/CPRA):**
- **Right to Know**: What data collected, sources, purposes, third parties
- **Right to Delete**: Self-service via app (password required) - IRREVOCABLE
- **Right to Correct**: Update personal data anytime in app
- **Right to Limit SPI Use**: Limit sensitive data processing
- **Right to Opt-Out**: If sale/sharing ever introduced
- **Right to Data Portability**: Request data in JSON/CSV format
- **Right to Non-Discrimination**: No penalty for exercising rights

**10. How to Exercise Rights:**
- Online Portal: [Privacy Portal URL]
- Email: privacy@cultioo.com
- Response time: 45 days (may extend to 90 days)
- Free of charge (reasonable frequency)

**11. Data Retention:**
- Account data: Until deletion by user
- Transaction data: 7 years (IRS tax requirements)
- Messages: Until account deletion or request
- Usage/Technical data: 12-24 months
- Location: Device only - NO server storage

**12. Minors:**
- App NOT intended for children under 13 (COPPA)
- No knowing collection from children under 13
- California users under 18: highest privacy settings by default

**13. Messenger Function:**
- Message history stored for both parties
- Only sender and recipient have access
- Cultioo access only for: fraud investigation, legal compliance, technical issues (with consent)
- Messages classified as Sensitive Personal Information (SPI)

**14. Contact for Privacy Questions:**
- Email: privacy@cultioo.com
- General: support@cultioo.com

IMPORTANT: For full privacy details, users should read the complete Privacy Policy at www.cultioo.com or contact privacy@cultioo.com.

You are Cully, the professional AI Business Assistant from Cultioo. Always respond efficiently, professionally, and with accurate financial data when available.
""";

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Appearance animation
    _appearanceAnimationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _appearanceAnimationController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _appearanceAnimationController,
      curve: Curves.easeOut,
    ));

    // Listen to text changes for button animation
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }
    });

    // Start appearance animation
    _appearanceAnimationController.forward();

    _loadChatHistory();
  }

  @override
  void dispose() {
    _typingAnimationController.dispose();
    _appearanceAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('cully_chat_history');
      if (historyJson != null) {
        final List<dynamic> history = json.decode(historyJson);
        if (mounted) {
          setState(() {
            _messages = history
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
      if (_messages.isEmpty) {
        _addWelcomeMessage();
      }
    } catch (e) {
      _addWelcomeMessage();
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cully_chat_history', json.encode(_messages));
    } catch (e) {
      print('Error saving chat history: $e');
    }
  }

  void _addWelcomeMessage() {
    if (!mounted) return;
    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': AppLocalizations.of(context)!.heyCullyGreeting,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    _messageController.clear();
    _focusNode.unfocus();

    if (!mounted) return;
    setState(() {
      _messages.add({
        'role': 'user',
        'content': message,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _isLoading = true;
      _isTyping = true;
    });

    _scrollToBottom();
    await _saveChatHistory();

    try {
      final response = await _getCullyResponse(message);

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'role': 'assistant',
            'content': response,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _isLoading = false;
        });
        _scrollToBottom();
        await _saveChatHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'role': 'assistant',
            'content': AppLocalizations.of(context)!.anErrorOccurredPleaseTryAgain,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<String> _getCullyResponse(String userMessage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http
          .post(
            Uri.parse('${AppConfig.apiUrl}/chat/cully'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'message': userMessage,
              'context': _cultiooContext,
              'history': _messages.take(10).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response'] ?? "I couldn't generate a response.";
      } else {
        return _getLocalResponse(userMessage);
      }
    } catch (e) {
      print('Error getting Cully response: $e');
      return _getLocalResponse(userMessage);
    }
  }

  String _getLocalResponse(String userMessage) {
    final lowerMessage = userMessage.toLowerCase();

    // Greetings
    if (lowerMessage.contains('hello') ||
        lowerMessage.contains('hi') ||
        lowerMessage.contains('hey')) {
      return AppLocalizations.of(context)!.helloHowCanIAssistYouWithYourBusinessNeed;
    }

    // Credit & Limits
    if (lowerMessage.contains('credit') || lowerMessage.contains('limit')) {
      return 'Regarding credit limits:\n\n• New accounts start with a **\$75,000** credit limit\n• Limits are validated based on Middesk and D&B credit checks\n• To request a limit increase, contact support@cultioo.com with your payment history\n\nYour available credit determines your ordering capacity.';
    }

    // Terms of Service / TOS / Legal
    if (lowerMessage.contains('terms') ||
        lowerMessage.contains('tos') ||
        lowerMessage.contains('legal') ||
        lowerMessage.contains('liability') ||
        lowerMessage.contains('arbitration') ||
        lowerMessage.contains('warranty') ||
        lowerMessage.contains('refund')) {
      return '**Terms of Service Summary:**\n\n📋 Cultioo is a **technology platform** (marketplace intermediary)\n⚖️ Products sold **"AS-IS"** by sellers\n⏰ **30-day reporting period** for issues after delivery\n🔒 **Binding arbitration** required (no class actions)\n📍 Governed by **Delaware law**\n\nKey contacts:\n• Legal: legal@cultioo.com\n• Disputes: disputes@cultioo.com\n\nFor full TOS details, visit www.cultioo.com or contact legal@cultioo.com.';
    }

    // Privacy Policy / Data Protection
    if (lowerMessage.contains('privacy') ||
        lowerMessage.contains('data') ||
        lowerMessage.contains('gdpr') ||
        lowerMessage.contains('ccpa') ||
        lowerMessage.contains('personal information') ||
        lowerMessage.contains('delete my') ||
        lowerMessage.contains('my rights')) {
      return '**Privacy Policy Summary:**\n\n🔒 **Data Security**: Passwords hashed (bcrypt), all transmissions encrypted (TLS)\n📍 **Location**: Stored ONLY on your device - NEVER sent to servers\n💳 **Payments**: Only last 4 digits stored - full data with Stripe\n🚫 **No Sale**: We do NOT sell your personal information\n\n**Your Rights (CCPA/CPRA):**\n• Right to Know, Delete, Correct\n• Right to Data Portability\n• Right to Non-Discrimination\n\n📧 Privacy questions: privacy@cultioo.com\n\nFor full details, visit www.cultioo.com/privacy';
    }

    // Late Fee / 15% Rule
    if (lowerMessage.contains('late') ||
        lowerMessage.contains('fee') ||
        lowerMessage.contains('15%') ||
        lowerMessage.contains('overdue')) {
      return '**The 15% Late Fee Policy:**\n\nPayments are due within the agreed Net 30 or Net 60 terms. On **day 31** (or day 61 for Net 60), an automatic **15% late fee** is applied.\n\nThis policy ensures our drivers are paid within **14 days** and keeps the agricultural supply chain moving efficiently.\n\n*This is based on our standard Terms of Service (AGB).*';
    }

    // Driver Payout
    if (lowerMessage.contains('driver') ||
        lowerMessage.contains('payout') ||
        lowerMessage.contains('trucker')) {
      return 'Driver Payout Policy:\n\n🚛 Drivers are paid within **14 days** after successful delivery\n💰 This is funded by our Net 30/60 credit model\n📋 The **15% late fee** ensures driver compensation remains guaranteed\n\nThis system keeps the agricultural supply chain moving efficiently.';
    }

    // Payment Terms
    if (lowerMessage.contains('net 30') ||
        lowerMessage.contains('net 60') ||
        lowerMessage.contains('payment term')) {
      return 'Cultioo offers flexible payment terms:\n\n• **Net 30**: Payment due within 30 days\n• **Net 60**: Payment due within 60 days\n\nPayments are processed securely via Stripe. Remember: Late payments incur a **15% fee** starting day 31/61.';
    }

    // Payments
    if (lowerMessage.contains('pay') ||
        lowerMessage.contains('payment') ||
        lowerMessage.contains('stripe')) {
      return AppLocalizations.of(context)!.cultiooPaymentOptionsnnCreditCardVisaMasterc;
    }

    // Orders & Approval
    if (lowerMessage.contains('order') ||
        lowerMessage.contains('approval') ||
        lowerMessage.contains('pending') ||
        lowerMessage.contains('admin')) {
      return AppLocalizations.of(context)!.orderApprovalWorkflownn1OrdersCreatedByTeam;
    }

    // Invoice
    if (lowerMessage.contains('invoice') || lowerMessage.contains('bill')) {
      return AppLocalizations.of(context)!.invoiceManagementnnViewAllInvoicesInYourAcc;
    }

    // Delivery & Shipping & Insurance
    if (lowerMessage.contains('deliver') ||
        lowerMessage.contains('shipping') ||
        lowerMessage.contains('cargo') ||
        lowerMessage.contains('insurance') ||
        lowerMessage.contains('damage')) {
      return AppLocalizations.of(context)!.logisticsInsurancennAllCargoIsFullyInsuredD;
    }

    // Support & Contact
    if (lowerMessage.contains('contact') ||
        lowerMessage.contains('support') ||
        lowerMessage.contains('help')) {
      return AppLocalizations.of(context)!.cultiooSupportnnSupportcultioocomnWwwcultioocom;
    }

    // Products
    if (lowerMessage.contains('product') ||
        lowerMessage.contains('buy') ||
        lowerMessage.contains('source')) {
      return AppLocalizations.of(context)!.agriculturalProductsOnCultioonnFruitsVegetabl;
    }

    // Corporate Structure
    if (lowerMessage.contains('company') ||
        lowerMessage.contains('corporate') ||
        lowerMessage.contains('shares') ||
        lowerMessage.contains('structure') ||
        lowerMessage.contains('delaware') ||
        lowerMessage.contains('c-corp')) {
      return '**Cultioo Corporate Structure:**\n\n🏛️ **C-Corporation** incorporated in Delaware, USA\n📊 **10,000,000** authorized shares\n💵 Par value: \$0.00001 per share\n🔐 EIN: 32-0759593\n\nThis structure provides optimal flexibility for growth and investment.';
    }

    // About Cultioo
    if (lowerMessage.contains('cultioo') ||
        lowerMessage.contains('what is') ||
        lowerMessage.contains('about')) {
      return 'Cultioo is a leading **US-based agricultural logistics platform**.\n\n🏛️ **C-Corporation** (Delaware)\n\nWe provide:\n• B2B/B2C marketplace for agricultural products\n• **Net 30/60** payment terms (15% late fee rule)\n• Secure Stripe virtual accounts\n• Full cargo insurance\n• Driver payout within **14 days**\n\nOur mission: Streamline the agricultural supply chain.';
    }

    // Thanks
    if (lowerMessage.contains('thank') || lowerMessage.contains('thanks')) {
      return "You're welcome. If you have any further business questions, I'm here to help.";
    }

    // Default professional response
    return "I'm Cully, your Cultioo Business Assistant. 📊\n\nI have access to your account data! Try asking:\n• \"How many orders do I have?\"\n• \"What's my credit limit?\"\n• \"Am I a business account?\"\n• \"Show my recent orders\"\n\nOr ask about Cultioo policies, payments, and more!";
  }

  Future<void> _confirmClearChat() async {
    final loc = AppLocalizations.of(context)!;
    final isDark = widget.isDark;

    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              CupertinoIcons.trash,
              size: 36,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              loc.clearAll,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.thisActionCannotBeUndoneTheOrderWillBePer,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            TradeRepublicButton(
              label: loc.delete,
              isDestructive: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            TradeRepublicButton(
              label: loc.cancel,
              isSecondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await _clearChatHistory();
    }
  }

  Future<void> _clearChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cully_chat_history');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _messages = [];
    });
    _addWelcomeMessage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark ? const Color(0xFF000000) : Colors.white,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (defaultTargetPlatform == TargetPlatform.macOS ||
                          defaultTargetPlatform == TargetPlatform.windows ||
                          defaultTargetPlatform == TargetPlatform.linux) &&
                      MediaQuery.of(context).size.width > 900
                      ? 820.0
                      : double.infinity,
                ),
                child: Column(
                  children: [
                    Expanded(child: _buildMessagesList()),
                    if (_isTyping) _buildTypingIndicator(),
                    _buildInputArea(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      toolbarHeight: Platform.isMacOS ? 100 : null,
      backgroundColor: widget.isDark ? const Color(0xFF000000) : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      leadingWidth: 72,
      leading: Container(
        alignment: Alignment.center,
        margin: EdgeInsets.only(
          left: 20,
          top: Platform.isMacOS ? 20 : 0,
        ),
        child: TradeRepublicButton(
          icon: Icon(
            CupertinoIcons.chevron_back,
            size: 18,
          ),
          isSecondary: true,
          width: 44,
          height: 44,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(25),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: Container(
        margin: EdgeInsets.only(top: Platform.isMacOS ? 20 : 0),
        child: Row(
        children: [
          // Cully Avatar - smaller size
          ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Image.asset(
              widget.isDark ? 'logo/cully_dark.png' : 'logo/cully_light.png',
              width: 22,
              height: 22,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Cully',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: widget.isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: const Text(
                        'AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  AppLocalizations.of(context)!.alwaysOnline,
                  style: TextStyle(
                    fontSize: 11,
                    color: const Color(0xFF34C759),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      actions: [
        Container(
          margin: EdgeInsets.only(
            top: Platform.isMacOS ? 20 : 0,
            right: 20,
          ),
          child: TradeRepublicButton(
            icon: const Icon(CupertinoIcons.trash),
            isSecondary: true,
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(25),
            onPressed: _confirmClearChat,
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: Platform.isMacOS ? 80 : 20,
        bottom: 20,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isUser = message['role'] == 'user';
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 300 + (index * 50)),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: _buildMessageBubble(message, isUser),
        );
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isUser) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset((isUser ? 30 : -30) * (1 - value), 0),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: EdgeInsets.only(
                left: isUser ? 60 : 0,
                right: isUser ? 0 : 60,
                bottom: 12,
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? (widget.isDark ? Colors.white : Colors.black)
                          : (widget.isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04)),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      message['content'] ?? '',
                      style: TextStyle(
                        color: isUser
                            ? (widget.isDark ? Colors.black : Colors.white)
                            : (widget.isDark ? Colors.white : Colors.black),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _formatTime(message['timestamp']),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.4)
                            : Colors.black.withOpacity(0.4),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _typingAnimationController,
                  builder: (context, child) {
                    final offset = (index * 0.2);
                    final value =
                        ((_typingAnimationController.value + offset) % 1.0);
                    final opacity = (0.3 + 0.7 * (1 - (value - 0.5).abs() * 2))
                        .clamp(0.3, 1.0);
                    return Container(
                      margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: (widget.isDark ? Colors.white : Colors.black)
                            .withOpacity(opacity * 0.6),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      margin: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        children: [
          // Thin divider line above input
          Container(
            height: 1,
            color: widget.isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.08),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Text input
              Expanded(
                child: TradeRepublicTextField(
                  controller: _messageController,
                  hintText: AppLocalizations.of(context)!.messageCully,
                  maxLines: 4,
                  minLines: 1,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 12),
              // Send button
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                child: _isLoading
                    ? Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CultiooLoadingIndicator(),
                          ),
                        ),
                      )
                    : TradeRepublicButton(
                        icon: const Icon(CupertinoIcons.arrow_up, size: 16),
                        isSecondary: true,
                        width: 44,
                        height: 44,
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(25),
                        onPressed: _hasText ? _sendMessage : null,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final DateTime dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return AppLocalizations.of(context)!.now;
      }
    } catch (e) {
      return '';
    }
  }
}
