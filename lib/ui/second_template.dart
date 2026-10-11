// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:flutter/material.dart';
// import 'package:inappify_sdk/helpers/color_helper.dart';
// import 'package:inappify_sdk/inappify_sdk.dart';
// import 'package:inappify_sdk/models/enums/market.dart';
// import 'package:inappify_sdk/models/enums/purchase_status.dart';
// import 'package:inappify_sdk/models/paywall_model.dart';
// import 'package:inappify_sdk/models/purchase_result.dart';
// import 'package:url_launcher/url_launcher.dart';

// class SecondTemplate extends StatefulWidget {
//   const SecondTemplate({
//     required this.paywallModel,
//     required this.market,
//     super.key,
//   });

//   final PaywallModel paywallModel;
//   final Market market;

//   @override
//   State<SecondTemplate> createState() => _SecondTemplateState();
// }

// class _SecondTemplateState extends State<SecondTemplate> {
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
//     return Stack(
//       children: [
//         Positioned.fill(
//           child: Container(
//             color: ColorHelper.getColorFromHex(widget
//                     .paywallModel.paywall?.template?.background?.color?.first ??
//                 ''),
//           ),
//         ),
//         Positioned(
//           top: 0,
//           left: 0,
//           right: 0,
//           bottom: MediaQuery.sizeOf(context).height * 0.5,
//           child: CachedNetworkImage(
//             width: double.infinity,
//             imageUrl:
//                 widget.paywallModel.paywall?.template?.background?.image ?? '',
//             fit: BoxFit.cover,
//           ),
//         ),
//         Positioned(
//           bottom: 0,
//           left: 0,
//           right: 0,
//           top: MediaQuery.sizeOf(context).height * 0.35,
//           child: Column(
//             children: [
//               Container(
//                 height: 70,
//                 decoration: BoxDecoration(
//                   gradient: LinearGradient(
//                     begin: Alignment.topCenter,
//                     end: Alignment.bottomCenter,
//                     colors: [
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                                   ?.template?.background?.color?.first ??
//                               '')
//                           .withOpacity(0.0),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                                   ?.template?.background?.color?.first ??
//                               '')
//                           .withOpacity(0.2),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                                   ?.template?.background?.color?.first ??
//                               '')
//                           .withOpacity(0.4),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                                   ?.template?.background?.color?.first ??
//                               '')
//                           .withOpacity(0.6),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                                   ?.template?.background?.color?.first ??
//                               '')
//                           .withOpacity(0.8),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                               ?.template?.background?.color?.first ??
//                           ''),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                               ?.template?.background?.color?.first ??
//                           ''),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                               ?.template?.background?.color?.first ??
//                           ''),
//                       ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                               ?.template?.background?.color?.first ??
//                           ''),
//                     ],
//                   ),
//                 ),
//                 child: Center(
//                   child: Text(
//                     widget.paywallModel.paywall?.template?.title ?? '',
//                     style: TextStyle(
//                         fontSize: 24,
//                         fontWeight: FontWeight.bold,
//                         color: ColorHelper.getColorFromHex(
//                             widget.paywallModel.paywall?.template?.text_color ??
//                                 '')),
//                   ),
//                 ),
//               ),
//               Expanded(
//                 child: Container(
//                   width: double.infinity,
//                   color: ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                           ?.template?.background?.color?.first ??
//                       ''),
//                   child: Column(
//                     children: [
//                       Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 16),
//                         child: Text(
//                           widget.paywallModel.paywall?.template?.sub_title ??
//                               '',
//                           textAlign: TextAlign.center,
//                           style: TextStyle(
//                             fontSize: 14,
//                             color: ColorHelper.getColorFromHex(
//                               widget.paywallModel.paywall?.template
//                                       ?.sub_text_color ??
//                                   '',
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(
//                         height: 32,
//                       ),
//                       Row(
//                         children: List.generate(
//                           widget.paywallModel.paywall?.template?.features
//                                   ?.length ??
//                               0,
//                           (index) => Expanded(
//                             child: Column(
//                               children: [
//                                 Text(
//                                   widget.paywallModel.paywall?.template
//                                           ?.features?[index].text ??
//                                       '',
//                                   style: TextStyle(
//                                     fontSize: 12,
//                                     fontWeight: FontWeight.bold,
//                                     color: ColorHelper.getColorFromHex(
//                                       widget.paywallModel.paywall?.template
//                                               ?.sub_text_color ??
//                                           '',
//                                     ),
//                                   ),
//                                 )
//                                 // CachedNetworkImage(
//                                 //   imageUrl: paywallModel.paywall?.template
//                                 //           ?.features?[index].icon ??
//                                 //       '',
//                                 // )
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),
//                       Expanded(
//                         child: Column(
//                           mainAxisAlignment: MainAxisAlignment.end,
//                           children: [
//                             SizedBox(
//                               height: 180,
//                               width: double.infinity,
//                               child: ListView.separated(
//                                 padding:
//                                     const EdgeInsets.symmetric(horizontal: 16),
//                                 scrollDirection: Axis.horizontal,
//                                 itemCount: widget.paywallModel.paywall
//                                         ?.offering_packages?.length ??
//                                     0,
//                                 separatorBuilder: (_, __) => const SizedBox(
//                                   width: 16,
//                                 ),
//                                 itemBuilder: (context, index) =>
//                                     GestureDetector(
//                                   onTap: () {
//                                     setState(() {
//                                       selectedPackageIndex = index;
//                                     });
//                                   },
//                                   child: AnimatedContainer(
//                                     duration: const Duration(milliseconds: 350),
//                                     width: 180,
//                                     padding: const EdgeInsets.all(12),
//                                     decoration: BoxDecoration(
//                                       borderRadius: BorderRadius.circular(16),
//                                       border: Border.all(
//                                         width: selectedPackageIndex == index
//                                             ? 2
//                                             : 1,
//                                         color: selectedPackageIndex == index
//                                             ? ColorHelper.getColorFromHex(
//                                                 widget
//                                                         .paywallModel
//                                                         .paywall
//                                                         ?.template
//                                                         ?.packages
//                                                         ?.selected_border_color ??
//                                                     '',
//                                               )
//                                             : ColorHelper.getColorFromHex(
//                                                 widget
//                                                         .paywallModel
//                                                         .paywall
//                                                         ?.template
//                                                         ?.packages
//                                                         ?.default_border_color ??
//                                                     '',
//                                               ),
//                                       ),
//                                     ),
//                                     child: Column(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceBetween,
//                                       crossAxisAlignment:
//                                           CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           widget
//                                                   .paywallModel
//                                                   .paywall
//                                                   ?.offering_packages?[index]
//                                                   .description ??
//                                               '',
//                                           style: TextStyle(
//                                             fontSize: 16,
//                                             fontWeight: FontWeight.w700,
//                                             color: ColorHelper.getColorFromHex(
//                                               widget
//                                                       .paywallModel
//                                                       .paywall
//                                                       ?.template
//                                                       ?.packages
//                                                       ?.default_text_color ??
//                                                   '',
//                                             ),
//                                           ),
//                                         ),
//                                         Text(
//                                           '${widget.paywallModel.paywall?.offering_packages?[index].products?.first.price?.toInt().toString() ?? ''} ریال',
//                                           style: TextStyle(
//                                             fontSize: 16,
//                                             fontWeight: FontWeight.w700,
//                                             color: ColorHelper.getColorFromHex(
//                                               widget
//                                                       .paywallModel
//                                                       .paywall
//                                                       ?.template
//                                                       ?.packages
//                                                       ?.default_text_color ??
//                                                   '',
//                                             ),
//                                           ),
//                                         ),
//                                         Text(
//                                           widget
//                                                   .paywallModel
//                                                   .paywall
//                                                   ?.offering_packages?[index]
//                                                   .description ??
//                                               '',
//                                           style: TextStyle(
//                                             fontSize: 16,
//                                             fontWeight: FontWeight.w700,
//                                             color: ColorHelper.getColorFromHex(
//                                               widget
//                                                       .paywallModel
//                                                       .paywall
//                                                       ?.template
//                                                       ?.packages
//                                                       ?.default_text_color ??
//                                                   '',
//                                             ),
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             )
//                           ],
//                         ),
//                       ),
//                       const SizedBox(
//                         height: 24,
//                       ),
//                       Container(
//                         margin: const EdgeInsets.symmetric(horizontal: 16),
//                         width: double.infinity,
//                         height: 45,
//                         child: ElevatedButton(
//                           onPressed: () {},
//                           style: ButtonStyle(
//                             backgroundColor: WidgetStatePropertyAll(
//                               ColorHelper.getColorFromHex(
//                                 widget.paywallModel.paywall?.template?.buttons
//                                         ?.main?.color ??
//                                     '',
//                               ),
//                             ),
//                           ),
//                           child: Text(
//                             widget.paywallModel.paywall?.template?.buttons?.main
//                                     ?.text ??
//                                 '',
//                           ),
//                         ),
//                       ),
//                       TextButton(
//                         onPressed: () async {
//                           PurchaseResult? purchaseResult =
//                               await InappifySdk.purchase(
//                                   productIdentifier: widget
//                                           .paywallModel
//                                           .paywall
//                                           ?.offering_packages?[
//                                               selectedPackageIndex!]
//                                           .products
//                                           ?.first
//                                           .identifier_key ??
//                                       '',
//                                   isCrypto: true);
//                           if (purchaseResult != null) {
//                             if (purchaseResult.purchaseStatus ==
//                                 PurchaseStatus.DONE) {
//                               await InappifySdk.getCustomerInfo();
//                             } else if (purchaseResult.purchaseStatus ==
//                                 PurchaseStatus.NEEDTOPAY) {
//                               await launchUrl(
//                                 Uri.parse(
//                                   purchaseResult.url ?? '',
//                                 ),
//                               );
//                             }
//                           }
//                         },
//                         child: Text(
//                           widget.paywallModel.paywall?.template?.buttons?.crypto
//                                   ?.text ??
//                               '',
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                             color: ColorHelper.getColorFromHex(
//                               widget.paywallModel.paywall?.template?.buttons
//                                       ?.crypto?.text_color ??
//                                   '',
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(
//                         height: 24,
//                       ),
//                     ],
//                   ),
//                 ),
//               )
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }
