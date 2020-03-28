import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final StreamController<BluetoothState> streamController = StreamController();
  StreamSubscription<BluetoothState> _streamBluetooth;
  StreamSubscription<RangingResult> _streamRanging;
  final _regionBeacons = <Region, List<Beacon>>{};
  final _beacons = <Beacon>[];
  bool authorizationStatusOk = false;
  bool locationServiceEnabled = false;
  bool bluetoothEnabled = false;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);

    super.initState();

    listeningState();

  }

  listeningState() async {
    print('Listening to bluetooth state');
    _streamBluetooth = flutterBeacon
        .bluetoothStateChanged()
        .listen((BluetoothState state) async {
      print('BluetoothState = $state');
      streamController.add(state);

      switch (state) {
        case BluetoothState.stateOn:
          initScanBeacon();
          break;
        case BluetoothState.stateOff:
          await pauseScanBeacon();
          await checkAllRequirements();
          break;
      }
    });
  }





  checkAllRequirements() async {
    final bluetoothState = await flutterBeacon.bluetoothState;
    final bluetoothEnabled = bluetoothState == BluetoothState.stateOn;
    final authorizationStatus = await flutterBeacon.authorizationStatus;
    final authorizationStatusOk =
        authorizationStatus == AuthorizationStatus.allowed ||
            authorizationStatus == AuthorizationStatus.always;
    final locationServiceEnabled =
        await flutterBeacon.checkLocationServicesIfEnabled;

    setState(() {
      this.authorizationStatusOk = authorizationStatusOk;
      this.locationServiceEnabled = locationServiceEnabled;
      this.bluetoothEnabled = bluetoothEnabled;
    });
  }

  initScanBeacon() async {
    await flutterBeacon.initializeScanning;
    await checkAllRequirements();
    if (!authorizationStatusOk ||
        !locationServiceEnabled ||
        !bluetoothEnabled) {
      print('RETURNED, authorizationStatusOk=$authorizationStatusOk, '
          'locationServiceEnabled=$locationServiceEnabled, '
          'bluetoothEnabled=$bluetoothEnabled');
      return;
    }
    final regions = <Region>[
      Region(
        identifier: 'demo',
        proximityUUID: '67090718-0509-0005-0000-000a01084134',
      ),
    ];

    if (_streamRanging != null) {
      if (_streamRanging.isPaused) {
        _streamRanging.resume();
        return;
      }
    }

    _streamRanging =
        flutterBeacon.ranging(regions).listen((RangingResult result) {
      print(result);
      if (result != null && mounted) {
        setState(() {
          _regionBeacons[result.region] = result.beacons;
          _beacons.clear();
          _regionBeacons.values.forEach((list) {
            _beacons.addAll(list);
          });
          _beacons.sort(_compareParameters);
        });
      }
    });
  }

  pauseScanBeacon() async {
    _streamRanging?.pause();
    if (_beacons.isNotEmpty) {
      setState(() {
        _beacons.clear();
      });
    }
  }

  int _compareParameters(Beacon a, Beacon b) {
    int compare = a.proximityUUID.compareTo(b.proximityUUID);

    if (compare == 0) {
      compare = a.major.compareTo(b.major);
    }

    if (compare == 0) {
      compare = a.minor.compareTo(b.minor);
    }

    return compare;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print('AppLifecycleState = $state');
    if (state == AppLifecycleState.resumed) {
      if (_streamBluetooth != null && _streamBluetooth.isPaused) {
        _streamBluetooth.resume();
      }
      await checkAllRequirements();
      if (authorizationStatusOk && locationServiceEnabled && bluetoothEnabled) {
        await initScanBeacon();
      } else {
        await pauseScanBeacon();
        await checkAllRequirements();
      }
    } else if (state == AppLifecycleState.paused) {
      _streamBluetooth?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    streamController?.close();
    _streamRanging?.cancel();
    _streamBluetooth?.cancel();
    flutterBeacon.close;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          primaryColor: Colors.white,
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        home: Scaffold(
            appBar: AppBar(
              title: const Text('Flutter Beacon'),
              centerTitle: false,
              actions: <Widget>[
                if (!authorizationStatusOk)
                  IconButton(
                      icon: Icon(Icons.portable_wifi_off),
                      color: Colors.red,
                      onPressed: () async {
                        await flutterBeacon.requestAuthorization;
                      }),
                if (!locationServiceEnabled)
                  IconButton(
                      icon: Icon(Icons.location_off),
                      color: Colors.red,
                      onPressed: () async {
                        if (Platform.isAndroid) {
                          await flutterBeacon.openLocationSettings;
                        } else if (Platform.isIOS) {}
                      }),
                StreamBuilder<BluetoothState>(
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final state = snapshot.data;

                      if (state == BluetoothState.stateOn) {
                        return IconButton(
                          icon: Icon(Icons.bluetooth_connected),
                          onPressed: () {},
                          color: Colors.lightBlueAccent,
                        );
                      }

                      if (state == BluetoothState.stateOff) {
                        return IconButton(
                          icon: Icon(Icons.bluetooth),
                          onPressed: () async {
                            if (Platform.isAndroid) {
                              try {
                                await flutterBeacon.openBluetoothSettings;
                              } on PlatformException catch (e) {
                                print(e);
                              }
                            } else if (Platform.isIOS) {}
                          },
                          color: Colors.red,
                        );
                      }

                      return IconButton(
                        icon: Icon(Icons.bluetooth_disabled),
                        onPressed: () {},
                        color: Colors.grey,
                      );
                    }

                    return SizedBox.shrink();
                  },
                  stream: streamController.stream,
                  initialData: BluetoothState.stateUnknown,
                ),
              ],
            ),
            body: _getpages()));
  }


  Set<int> _data = new Set();
  Set<int> _data2 = new Set();

  _getpages() {
    if (_beacons == null) {
      return Center(
        child: CircularProgressIndicator(),
      );
    } else if (_beacons.isEmpty) {

      if(_data.isEmpty || _data2.isEmpty)
        {
          return Center(
            child: CircularProgressIndicator(),
          );
        }
      else{

     return Padding(
       padding: const EdgeInsets.all(8.0),
       child: Container(
         width: 300,
         height: 90,
         decoration: BoxDecoration(

             borderRadius:  BorderRadius.all(Radius.circular(10)),
           color: Colors.grey[100]

         ),
         child: Column(
           mainAxisAlignment: MainAxisAlignment.start,
           crossAxisAlignment: CrossAxisAlignment.start,
           children: <Widget>[

             Padding(
               padding: const EdgeInsets.only(bottom:8.0, left:8, right: 8, top:12),
               child: Text("Major: ${_data2.last}"),
             ),
             Padding(
               padding: const EdgeInsets.all(8.0),
               child: Text("Minor: ${_data.last}"),
             ),
           ],
         ),
       ),
     );

        }

    }

    else  {

      return Container(

        child: ListView(
          children: ListTile.divideTiles(
              context: context,
              tiles: _beacons.map((beacon) {

                _data.add(beacon.minor);
                _data2.add(beacon.major);


                return ListTile(
                  title: Text(beacon.proximityUUID),
                  subtitle: new Row(
                    mainAxisSize: MainAxisSize.max,
                    children: <Widget>[
                      Flexible(
                          child: Text(
                              'Major: ${beacon.major}\nMinor: ${beacon.minor}',
                              style: TextStyle(fontSize: 13.0)),
                          flex: 1,
                          fit: FlexFit.tight),
                      Flexible(
                          child: Text(
                              'Accuracy: ${beacon.accuracy}m\nRSSI: ${beacon.rssi}',
                              style: TextStyle(fontSize: 13.0)),
                          flex: 2,
                          fit: FlexFit.tight)
                    ],
                  ),
                );
              })).toList(),
        ),
      );
    }
  }
}
