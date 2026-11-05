import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'core/widgets/modern_button.dart';
void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const MaterialApp(home: CameraSpike())); }
class CameraSpike extends StatefulWidget {
 const CameraSpike({super.key});
 @override State<CameraSpike> createState()=>_CameraSpikeState();
}
class _CameraSpikeState extends State<CameraSpike> with WidgetsBindingObserver {
 CameraController? controller; Uint8List? photo;
 bool busy=false; int generation=0; String status='Chọn mở camera. Chỉ chụp người đã đồng ý.';
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
 Future<void> open() async {
  final current=++generation;final previous=controller;controller=null;
  setState((){busy=true;status='Đang mở camera';}); CameraController? candidate;
  try {
   await previous?.dispose();final cameras=await availableCameras();
   if(cameras.isEmpty)throw CameraException('NO_CAMERA','Không có camera');
   final front=cameras.where((c)=>c.lensDirection==CameraLensDirection.front);
   candidate=CameraController(front.isEmpty?cameras.first:front.first,ResolutionPreset.medium,enableAudio:false);
   await candidate.initialize();
   if(!mounted||generation!=current){await candidate.dispose();return;}
   setState((){controller=candidate;status='Camera sẵn sàng';});
  } catch(_){await candidate?.dispose();if(mounted&&generation==current)setState(()=>status='Không mở được camera. Kiểm tra quyền và HTTPS hoặc localhost.');}
  finally{if(mounted&&generation==current)setState(()=>busy=false);}
 }
 Future<void> capture() async {
  final active=controller;final current=generation;
  if(active==null||!active.value.isInitialized||busy)return;
  setState(()=>busy=true);
  try{final f=await active.takePicture();final bytes=await f.readAsBytes();
   if(mounted&&generation==current)setState((){photo=bytes;status='Ảnh thử tại máy. Chưa xác minh danh tính.';});
  }catch(_){if(mounted&&generation==current)setState(()=>status='Không chụp được ảnh. Hãy mở lại camera.');}
  finally{if(mounted&&generation==current)setState(()=>busy=false);}
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state==AppLifecycleState.inactive||state==AppLifecycleState.paused){++generation;final old=controller;controller=null;old?.dispose();if(mounted)setState((){busy=false;status='Camera tạm dừng. Mở lại khi quay về.';});}
 }
 @override void dispose(){++generation;WidgetsBinding.instance.removeObserver(this);controller?.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Thử camera tuần 1')),body:ListView(padding:const EdgeInsets.all(16),children:[
  Text(status),const Text('Ảnh không upload. Plugin có thể lưu file cache riêng của ứng dụng.'),
  if(controller?.value.isInitialized??false)SizedBox(height:280,child:CameraPreview(controller!)),
  ModernButton(onPressed:open,text:'Mở camera',isLoading:busy,icon:Icons.camera_alt),
  Wrap(spacing:12,children:[FilledButton(onPressed:busy?null:capture,child:const Text('Chụp')),TextButton(onPressed:()=>setState(()=>photo=null),child:const Text('Xóa ảnh hiển thị'))]),
  if(photo!=null)Image.memory(photo!,height:280),
 ]));
}
