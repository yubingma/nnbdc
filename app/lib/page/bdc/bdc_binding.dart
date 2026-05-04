import 'package:get/get.dart';
import 'controllers/bdc_controller.dart';

class BdcBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BdcController>(() => BdcController());
  }
}
