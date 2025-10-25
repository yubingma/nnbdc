import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class XXXPage extends StatefulWidget {
  const XXXPage({super.key});

  @override
  XXXPageState createState() {
    return XXXPageState();
  }
}

class XXXPageState extends State<XXXPage> {
  bool dataLoaded = false;

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() {
      dataLoaded = true;
    });
  }

  Widget renderPage() {
    return const Column();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: '用户使用协议',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: Container(
        padding: const EdgeInsets.fromLTRB(leftPadding, 16, rightPadding, 0),
        child: (!dataLoaded) ? const Center(child: Text('')) : renderPage(),
      ),
    );
  }
}
