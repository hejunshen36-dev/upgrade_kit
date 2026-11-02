import {
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** UpgradeKitOhosPlugin **/
export default class UpgradeKitOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "UpgradeKitOhosPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "upgrade_kit");
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "checkAppUpdate":
        this.checkAppUpdate(result);
        break;
      case "showUpdateDialog":
        this.showUpdateDialog(result);
        break;
      case "installApk":
      case "openStore":
        result.error("unsupported", `${call.method} is not supported on OHOS.`, null);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private async checkAppUpdate(result: MethodResult): Promise<void> {
    const context = this.context;
    if (context == null) {
      result.error("no-ability", "A foreground UIAbility is required.", null);
      return;
    }
    try {
      const checkResult = await updateManager.checkAppUpdate(context);
      const available = checkResult.updateAvailable ===
        updateManager.UpdateAvailableCode.LATER_VERSION_EXIST;
      result.success(available ? "updateAvailable" : "noUpdate");
    } catch (error) {
      const businessError = error as BusinessError;
      result.error(
        "check-failed",
        `checkAppUpdate failed. code=${businessError.code}, message=${businessError.message}`,
        null,
      );
    }
  }

  private async showUpdateDialog(result: MethodResult): Promise<void> {
    const context = this.context;
    if (context == null) {
      result.error("no-ability", "A foreground UIAbility is required.", null);
      return;
    }
    try {
      const resultCode = await updateManager.showUpdateDialog(context);
      const shown = resultCode ===
        updateManager.ShowUpdateResultCode.SHOW_DIALOG_SUCCESS;
      result.success(shown ? "shown" : "notShown");
    } catch (error) {
      const businessError = error as BusinessError;
      result.error(
        "dialog-failed",
        `showUpdateDialog failed. code=${businessError.code}, message=${businessError.message}`,
        null,
      );
    }
  }
}
