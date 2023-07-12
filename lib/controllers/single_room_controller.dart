import 'dart:developer';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:get/get.dart';
import 'package:resonate/models/appwrite_room.dart';
import 'package:resonate/models/participant.dart';
import 'package:resonate/services/room_service.dart';

import '../utils/constants.dart';

class SingleRoomController extends GetxController {
  RxBool isLoading = false.obs;
  RxBool isMicOn = false.obs;
  Client client = Client();
  final AppwriteRoom appwriteRoom;
  late final Realtime realtime;
  late final Databases databases;
  late final User user;
  late final RealtimeSubscription? subscription;
  RxList<Rx<Participant>> participants = <Rx<Participant>>[].obs;

  SingleRoomController({required this.appwriteRoom});

  @override
  void onInit() async {
    super.onInit();
    client.setEndpoint(appwriteEndpoint).setProject(appwriteProjectId).setSelfSigned(status: true);
    realtime = Realtime(client);
    databases = Databases(client);
    await getParticipants();
    getRealtimeStream();
  }

  @override
  void onClose() async {
    subscription?.close();
    await leaveRoom();
    super.onClose();
  }

  Future<void> addParticipantDataToList(Document participant) async {
    Document userDataDoc = await databases.getDocument(
        databaseId: userDatabaseID, collectionId: usersCollectionID, documentId: participant.data["uid"]);
    final p = Rx(Participant(
        uid: participant.data["uid"],
        email: userDataDoc.data["email"],
        name: userDataDoc.data["name"],
        dpUrl: userDataDoc.data["profileImageUrl"],
        isAdmin: participant.data["isAdmin"],
        isMicOn: participant.data["isMicOn"],
        isModerator: participant.data["isModerator"],
        isSpeaker: participant.data["isSpeaker"]));
    participants.add(p);
  }

  Future<void> removeParticipantDataFromList(String uid) async {
    participants.removeWhere((p) => p.value.uid == uid);
  }

  Future<void> updateParticipantDataInList(Map<String,dynamic> payload) async {
    int toBeUpdatedIndex = participants.indexWhere((p) => p.value.uid==payload["uid"]);
    participants[toBeUpdatedIndex].value.isModerator = payload["isModerator"];
    participants[toBeUpdatedIndex].value.isMicOn = payload["isMicOn"];
    participants[toBeUpdatedIndex].value.isSpeaker = payload["isSpeaker"];
    update();
  }

  Future<void> getParticipants() async {
    try {
      isLoading.value = true;
      participants.value = <Rx<Participant>>[];
      var participantCollectionRef = await databases.listDocuments(
          databaseId: masterDatabaseId,
          collectionId: participantsCollectionId,
          queries: [Query.equal('roomId', appwriteRoom.id)]);
      for (Document participant in participantCollectionRef.documents) {
        addParticipantDataToList(participant);
      }
      update();
    } catch (e) {
      log(e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  void getRealtimeStream() {
    String channel = 'databases.$masterDatabaseId.collections.$participantsCollectionId.documents';
    subscription = realtime.subscribe([channel]);
    subscription?.stream.listen((data) {
      if (data.payload.isNotEmpty) {
        String roomId = data.payload["roomId"];
        if (roomId == appwriteRoom.id) {
          // This event belongs to the room current user is part of
          String docId = data.payload["\$id"];
          String action = data.events.first.substring(channel.length + 1 + docId.length + 1);

          switch (action) {
            case 'create':
              {
                addParticipantDataToList(Document.fromMap(data.payload));
                break;
              }
            case 'update':
              {
                updateParticipantDataInList(data.payload);
                break;
              }
            case 'delete':
              {
                removeParticipantDataFromList(data.payload["uid"]);
                break;
              }
          }
        }
        log(data.payload.toString());
      }
    });
  }

  Future<void> leaveRoom() async {
    await RoomService.leaveRoom(roomId: appwriteRoom.id);
  }

  Future<void> turnOnMic() async {
    await databases.updateDocument(
        databaseId: masterDatabaseId,
        collectionId: participantsCollectionId,
        documentId: appwriteRoom.myDocId!,
        data: {"isMicOn": true});
    isMicOn.value = true;
  }

  Future<void> turnOffMic() async {
    await databases.updateDocument(
        databaseId: masterDatabaseId,
        collectionId: participantsCollectionId,
        documentId: appwriteRoom.myDocId!,
        data: {"isMicOn": false});
    isMicOn.value = false;
  }
}
