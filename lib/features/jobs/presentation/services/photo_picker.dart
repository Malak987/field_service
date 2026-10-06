import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Where the photo comes from. Camera first: before photos document the
/// current site condition; the gallery stays available as a fallback.
enum PhotoPickSource { camera, gallery }

/// A successfully picked image. [path] may point at a temporary location —
/// callers must copy the bytes into app-owned storage immediately (the
/// repository does this via `LocalFileStorage`).
class PickedPhoto {
  const PickedPhoto({required this.path, this.mimeType});

  final String path;
  final String? mimeType;
}

/// Why picking failed — mapped to localized user messages by the page; raw
/// platform exceptions never reach the UI.
enum PhotoPickFailure {
  /// No camera available (desktop/simulator, no camera hardware, or no
  /// camera plugin on this platform).
  cameraUnavailable,

  /// The user/OS denied camera or photo-library access.
  accessDenied,

  /// The picked file could not be read as an image.
  invalidImage,

  /// Anything else.
  unknown,
}

class PhotoPickException implements Exception {
  const PhotoPickException(this.failure);

  final PhotoPickFailure failure;

  @override
  String toString() => 'PhotoPickException(${failure.name})';
}

/// Abstraction over `image_picker` so the widget layer stays testable and
/// the rest of the app never imports the plugin directly.
abstract interface class PhotoPicker {
  /// Opens the camera or the gallery and returns the picked image, or `null`
  /// when the user cancelled. Throws [PhotoPickException] on failure.
  Future<PickedPhoto?> pick({required PhotoPickSource source});
}

/// Production implementation backed by the existing `image_picker`
/// dependency.
///
/// `imageQuality: 85` applies the plugin's built-in JPEG re-encode: small
/// enough for mobile upload over field connections, still fully usable as site
/// documentation. No extra image-processing dependency is introduced.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? imagePicker})
    : _picker = imagePicker ?? ImagePicker();

  final ImagePicker _picker;

  static const int _imageQuality = 85;

  @override
  Future<PickedPhoto?> pick({required PhotoPickSource source}) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source == PhotoPickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: _imageQuality,
      );

      if (picked == null) {
        return null; // The user cancelled — not an error.
      }

      return PickedPhoto(path: picked.path, mimeType: picked.mimeType);
    } on PlatformException catch (error) {
      throw PhotoPickException(_mapPlatformError(error.code));
    } on MissingPluginException {
      // No camera/gallery plugin on this platform (desktop, tests).
      throw const PhotoPickException(PhotoPickFailure.cameraUnavailable);
    }
  }

  PhotoPickFailure _mapPlatformError(String? code) {
    switch (code) {
      case 'camera_access_denied':
      case 'photo_access_denied':
      case 'access_denied':
        return PhotoPickFailure.accessDenied;
      case 'no_available_camera':
        return PhotoPickFailure.cameraUnavailable;
      default:
        return PhotoPickFailure.unknown;
    }
  }
}
