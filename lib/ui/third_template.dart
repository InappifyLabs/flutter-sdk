// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:flutter/material.dart';
// import 'package:inappify_sdk/helpers/color_helper.dart';
// import 'package:inappify_sdk/inappify_sdk.dart';
// import 'package:inappify_sdk/models/enums/market.dart';
// import 'package:inappify_sdk/models/enums/purchase_status.dart';
// import 'package:inappify_sdk/models/paywall_model.dart';
// import 'package:inappify_sdk/models/purchase_result.dart';
// import 'package:url_launcher/url_launcher.dart';

// class ThirdTemplate extends StatefulWidget {
//   const ThirdTemplate({
//     required this.paywallModel,
//     required this.market,
//     super.key,
//   });

//   final PaywallModel paywallModel;
//   final Market market;

//   @override
//   State<ThirdTemplate> createState() => _ThirdTemplateState();
// }

// class _ThirdTemplateState extends State<ThirdTemplate> {
//   @override
//   Widget build(BuildContext context) => Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 16),
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.only(top: 16),
//               child: CachedNetworkImage(
//                 imageUrl: widget.paywallModel.paywall?.template?.icon ?? '',
//                 height: MediaQuery.sizeOf(context).height * 0.2,
//                 width: double.infinity,
//               ),
//             ),
//             const SizedBox(
//               height: 32,
//             ),
//             Text(
//               widget.paywallModel.paywall?.template?.title ?? '',
//               style: TextStyle(
//                 fontSize: 24,
//                 fontWeight: FontWeight.bold,
//                 color: ColorHelper.getColorFromHex(
//                   widget.paywallModel.paywall?.template?.text_color ?? '',
//                 ),
//               ),
//             ),
//             const SizedBox(
//               height: 24,
//             ),
//             Expanded(
//               child: Row(
//                 children: [
//                   Padding(
//                     padding: const EdgeInsets.only(right: 16),
//                     child: Column(
//                       children: List.generate(
//                         widget.paywallModel.paywall?.template?.features
//                                 ?.length ??
//                             0,
//                         (index) => Column(
//                           children: [
//                             Container(
//                               width: 24,
//                               height: 24,
//                               decoration: BoxDecoration(
//                                 shape: BoxShape.circle,
//                                 color: ColorHelper.getColorFromHex(widget
//                                         .paywallModel
//                                         .paywall
//                                         ?.template
//                                         ?.feature_border_color ??
//                                     ''),
//                               ),
//                             ),
//                             Container(
//                               width: 10,
//                               height: 80,
//                               decoration: BoxDecoration(
//                                 gradient: LinearGradient(
//                                   begin: Alignment.topCenter,
//                                   end: Alignment.bottomCenter,
//                                   colors: [
//                                     ColorHelper.getColorFromHex(widget
//                                                 .paywallModel
//                                                 .paywall
//                                                 ?.template
//                                                 ?.feature_border_color ??
//                                             '')
//                                         .withOpacity(
//                                             index == 0 ? 1 : 1 / (index + 1)),
//                                     ColorHelper.getColorFromHex(widget
//                                                 .paywallModel
//                                                 .paywall
//                                                 ?.template
//                                                 ?.feature_border_color ??
//                                             '')
//                                         .withOpacity(
//                                             index == 0 ? 0.5 : 1 / (index + 1))
//                                   ],
//                                 ),
//                               ),
//                             )
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                   Expanded(
//                     child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: List.generate(
//                           widget.paywallModel.paywall?.template?.features
//                                   ?.length ??
//                               0,
//                           (index) => SizedBox(
//                             height: 104,
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 Padding(
//                                   padding: const EdgeInsets.only(right: 8),
//                                   child: Text(
//                                     widget.paywallModel.paywall?.template
//                                             ?.features?[index].title ??
//                                         '',
//                                     style: TextStyle(
//                                       fontSize: 18,
//                                       fontWeight: FontWeight.bold,
//                                       color: ColorHelper.getColorFromHex(
//                                         widget.paywallModel.paywall?.template
//                                                 ?.text_color ??
//                                             '',
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                                 Text(
//                                   widget.paywallModel.paywall?.template
//                                           ?.features?[index].text ??
//                                       '',
//                                   style: TextStyle(
//                                     fontSize: 14,
//                                     fontWeight: FontWeight.bold,
//                                     color: ColorHelper.getColorFromHex(widget
//                                             .paywallModel
//                                             .paywall
//                                             ?.template
//                                             ?.sub_text_color ??
//                                         ''),
//                                   ),
//                                 )
//                               ],
//                             ),
//                           ),
//                         )),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(
//               height: 24,
//             ),
//             Text(
//               '${widget.paywallModel.paywall?.offering_packages?.first.products?.first.price?.toInt().toString() ?? ''}  ریال',
//               style: TextStyle(
//                 fontSize: 24,
//                 fontWeight: FontWeight.w700,
//                 color: ColorHelper.getColorFromHex(
//                   widget.paywallModel.paywall?.template?.buttons?.main?.color ??
//                       '',
//                 ),
//               ),
//             ),
//             const SizedBox(
//               height: 8,
//             ),
//             Container(
//               margin: const EdgeInsets.symmetric(horizontal: 16),
//               width: double.infinity,
//               height: 45,
//               child: ElevatedButton(
//                 onPressed: () {},
//                 style: ButtonStyle(
//                   shape: WidgetStatePropertyAll(
//                     RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(100),
//                     ),
//                   ),
//                   backgroundColor: WidgetStatePropertyAll(
//                     ColorHelper.getColorFromHex(widget.paywallModel.paywall
//                             ?.template?.buttons?.main?.color ??
//                         ''),
//                   ),
//                 ),
//                 child: Text(
//                   widget.paywallModel.paywall?.template?.buttons?.main?.text ??
//                       '',
//                 ),
//               ),
//             ),
//             TextButton(
//               onPressed: () async {
//                 PurchaseResult? purchaseResult = await InappifySdk.purchase(
//                     productIdentifier: widget
//                             .paywallModel
//                             .paywall
//                             ?.offering_packages
//                             ?.first
//                             .products
//                             ?.first
//                             .identifier_key ??
//                         '',
//                     isCrypto: true);
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
//               child: Text(
//                 widget.paywallModel.paywall?.template?.buttons?.crypto?.text ??
//                     '',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                   color: ColorHelper.getColorFromHex(
//                     widget.paywallModel.paywall?.template?.buttons?.crypto
//                             ?.text_color ??
//                         '',
//                   ),
//                 ),
//               ),
//             ),
//             const SizedBox(
//               height: 24,
//             ),
//           ],
//         ),
//       );
// }
