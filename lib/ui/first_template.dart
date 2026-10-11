// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:flutter/material.dart';
// import 'package:inappify_sdk/helpers/color_helper.dart';
// import 'package:inappify_sdk/inappify_sdk.dart';
// import 'package:inappify_sdk/models/enums/market.dart';
// import 'package:inappify_sdk/models/enums/purchase_status.dart';
// import 'package:inappify_sdk/models/paywall_model.dart';
// import 'package:inappify_sdk/models/purchase_result.dart';
// import 'package:url_launcher/url_launcher.dart';

// class FirstTemplate extends StatefulWidget {
//   const FirstTemplate({
//     required this.paywallModel,
//     required this.market,
//     super.key,
//   });

//   final PaywallModel paywallModel;
//   final Market market;

//   @override
//   State<FirstTemplate> createState() => _FirstTemplateState();
// }

// class _FirstTemplateState extends State<FirstTemplate> {
//   int? selectedPackageIndex;

//   @override
//   void initState() {
//     selectedPackageIndex =
//         (widget.paywallModel.paywall?.offering_packages?.isNotEmpty ?? false)
//             ? 0
//             : null;
//     super.initState();
//   }

//   @override
//   Widget build(BuildContext context) {
//     print(widget.paywallModel.paywall?.template?.icon ?? '');
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.only(top: 16),
//             child: CachedNetworkImage(
//               imageUrl: widget.paywallModel.paywall?.template?.icon ?? '',
//               height: MediaQuery.sizeOf(context).height * 0.2,
//               width: double.infinity,
//             ),
//           ),
//           const SizedBox(
//             height: 32,
//           ),
//           Text(
//             widget.paywallModel.paywall?.template?.title ?? '',
//             style: TextStyle(
//               fontSize: 24,
//               fontWeight: FontWeight.bold,
//               color: ColorHelper.getColorFromHex(
//                 widget.paywallModel.paywall?.template?.text_color ?? '',
//               ),
//             ),
//           ),
//           const SizedBox(
//             height: 12,
//           ),
//           Text(
//             widget.paywallModel.paywall?.template?.sub_title ?? '',
//             textAlign: TextAlign.center,
//             style: TextStyle(
//               fontSize: 14,
//               color: ColorHelper.getColorFromHex(
//                 widget.paywallModel.paywall?.template?.text_color ?? '',
//               ),
//             ),
//           ),
//           const SizedBox(
//             height: 12,
//           ),
//           Expanded(
//             child: ListView.separated(
//               padding: const EdgeInsets.only(top: 32),
//               itemCount:
//                   widget.paywallModel.paywall?.offering_packages?.length ?? 0,
//               separatorBuilder: (_, __) => const SizedBox(
//                 height: 12,
//               ),
//               itemBuilder: (context, index) => GestureDetector(
//                 onTap: () {
//                   setState(() {
//                     selectedPackageIndex = index;
//                   });
//                 },
//                 child: AnimatedContainer(
//                   duration: const Duration(milliseconds: 350),
//                   padding:
//                       const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(8),
//                     color: ColorHelper.getColorFromHex(
//                       index == selectedPackageIndex
//                           ? (widget.paywallModel.paywall?.template?.packages
//                                   ?.selected_background_color ??
//                               '')
//                           : widget.paywallModel.paywall?.template?.packages
//                                   ?.default_background_color ??
//                               '',
//                     ),
//                   ),
//                   child: Column(
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Row(
//                             children: [
//                               Container(
//                                 width: 16,
//                                 height: 16,
//                                 decoration: BoxDecoration(
//                                   shape: BoxShape.circle,
//                                   color: selectedPackageIndex == index
//                                       ? ColorHelper.getColorFromHex(widget
//                                               .paywallModel
//                                               .paywall
//                                               ?.template
//                                               ?.packages
//                                               ?.selected_text_color ??
//                                           '')
//                                       : null,
//                                   border: selectedPackageIndex == index
//                                       ? null
//                                       : Border.all(
//                                           width: 1,
//                                           color: Colors.white,
//                                         ),
//                                 ),
//                                 child: selectedPackageIndex == index
//                                     ? Center(
//                                         child: Icon(
//                                           Icons.check,
//                                           size: 14,
//                                           color: ColorHelper.getColorFromHex(widget
//                                                   .paywallModel
//                                                   .paywall
//                                                   ?.template
//                                                   ?.packages
//                                                   ?.selected_background_color ??
//                                               ''),
//                                         ),
//                                       )
//                                     : null,
//                               ),
//                               const SizedBox(
//                                 width: 8,
//                               ),
//                               Text(
//                                 widget
//                                         .paywallModel
//                                         .paywall
//                                         ?.offering_packages?[index]
//                                         .description ??
//                                     '',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: ColorHelper.getColorFromHex(
//                                     widget.paywallModel.paywall?.template
//                                             ?.packages?.default_text_color ??
//                                         '',
//                                   ),
//                                 ),
//                               )
//                             ],
//                           ),
//                           Text(
//                             '${widget.paywallModel.paywall?.offering_packages?[index].products?.first.price?.toInt().toString() ?? ''}  ریال',
//                             style: TextStyle(
//                               fontSize: 14,
//                               color: ColorHelper.getColorFromHex(
//                                 widget.paywallModel.paywall?.template?.packages
//                                         ?.default_text_color ??
//                                     '',
//                               ),
//                             ),
//                           )
//                         ],
//                       )
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(
//             height: 24,
//           ),
//           Container(
//             margin: const EdgeInsets.symmetric(horizontal: 16),
//             width: double.infinity,
//             height: 45,
//             child: ElevatedButton(
//               onPressed: () async {
//                 PurchaseResult? purchaseResult = await InappifySdk.purchase(
//                   productIdentifier: widget
//                           .paywallModel
//                           .paywall
//                           ?.offering_packages?[selectedPackageIndex!]
//                           .products
//                           ?.first
//                           .identifier_key ??
//                       '',
//                 );
//                 if (purchaseResult != null) {
//                   if (purchaseResult.purchaseStatus == PurchaseStatus.DONE) {
//                     await InappifySdk.getCustomerInfo();
//                   } else if (purchaseResult.purchaseStatus ==
//                       PurchaseStatus.NEEDTOPAY) {
//                     await launchUrl(
//                       Uri.parse(
//                         purchaseResult.url ?? '',
//                       ),
//                     );
//                   }
//                 }
//               },
//               style: ButtonStyle(
//                 shape: WidgetStatePropertyAll(
//                   RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(100),
//                   ),
//                 ),
//                 backgroundColor: WidgetStatePropertyAll(
//                   ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                           ?.template?.buttons?.main?.color ??
//                       ''),
//                 ),
//               ),
//               child: Text(
//                 widget.paywallModel.paywall?.template?.buttons?.main?.text ??
//                     '',
//               ),
//             ),
//           ),
//           TextButton(
//             onPressed: () async {
//               PurchaseResult? purchaseResult = await InappifySdk.purchase(
//                   productIdentifier: widget
//                           .paywallModel
//                           .paywall
//                           ?.offering_packages?[selectedPackageIndex!]
//                           .products
//                           ?.first
//                           .identifier_key ??
//                       '',
//                   isCrypto: true);
//               if (purchaseResult != null) {
//                 if (purchaseResult.purchaseStatus == PurchaseStatus.DONE) {
//                   await InappifySdk.getCustomerInfo();
//                 } else if (purchaseResult.purchaseStatus ==
//                     PurchaseStatus.NEEDTOPAY) {
//                   await launchUrl(
//                     Uri.parse(
//                       purchaseResult.url ?? '',
//                     ),
//                   );
//                 }
//               }
//             },
//             child: Text(
//               widget.paywallModel.paywall?.template?.buttons?.crypto?.text ??
//                   '',
//               style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: ColorHelper.getColorFromHex(
//                   widget.paywallModel.paywall?.template?.buttons?.crypto
//                           ?.text_color ??
//                       '',
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(
//             height: 24,
//           ),
//         ],
//       ),
//     );
//   }
// }
