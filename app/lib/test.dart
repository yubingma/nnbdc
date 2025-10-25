import 'package:flutter/material.dart';
import 'package:nnbdc/global.dart';
import 'package:image_network/image_network.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const TestPage());
}

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImageNetwork',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo ImageNetwork'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String imageUrl = "http://localhost/img/word/dictionary_0.jpg";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: widget.title,
      ),
      body: Center(
        child: ImageNetwork(
          image: imageUrl,
          height: 150,
          width: 150,
          duration: 1500,
          curve: Curves.easeIn,
          onPointer: true,
          debugPrint: false,
          fitAndroidIos: BoxFit.cover,
          fitWeb: BoxFitWeb.cover,
          onLoading: const CircularProgressIndicator(
            color: Colors.indigoAccent,
          ),
          onError: const Icon(
            Icons.error,
            color: Colors.red,
          ),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            showDialog(
                context: context,
                builder: (_) => const AlertDialog(
                      content: Text("©gabrielpatricksouza"),
                    ));
            Global.logger.d("©gabriel_patrick_souza");
          },
        ),
      ),
    );
  }
}
