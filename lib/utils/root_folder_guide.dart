const rootFolderGuide = <({String path, String description})>[
  (
    path: '/data/local/tmp',
    description: 'Temporary files used by ADB and developer tools. Files here may belong to active tools.',
  ),
  (
    path: '/data/local',
    description: 'Local developer-tool data. Advanced unlock is available for ordinary subfolders.',
  ),
  (
    path: '/data/adb/modules',
    description: 'Installed root modules and their configuration. Advanced unlock is available; edits can affect the next boot.',
  ),
  (
    path: '/data/adb/service.d',
    description: 'Root-manager scripts that run during late boot. Changes may run automatically with root privileges.',
  ),
  (
    path: '/data/adb/post-fs-data.d',
    description: 'Root-manager scripts used during early boot. Errors here can stop the phone from starting normally.',
  ),
  (
    path: '/data/adb',
    description: 'Root-manager modules, scripts and configuration. Advanced unlock is available; changes can break root access or boot.',
  ),
  (
    path: '/data/system',
    description: 'Android system-service state and settings. Incorrect edits can prevent normal startup.',
  ),
  (
    path: '/data/system_de',
    description: 'Android service state available before the first unlock after a reboot.',
  ),
  (
    path: '/data/system_ce',
    description: 'Encrypted Android service state that becomes available after unlocking.',
  ),
  (
    path: '/data/misc',
    description: 'Private state for Android services, such as connectivity and security components.',
  ),
  (
    path: '/data/app',
    description: 'Installed app packages managed by Android. Use the package installer to change apps.',
  ),
  (
    path: '/data/user_de',
    description: 'App data available before the first unlock after a reboot.',
  ),
  (
    path: '/data/user',
    description: 'Private app data, separated by Android user and app. Editing active app files can corrupt them.',
  ),
  (
    path: '/data/data',
    description: 'Private data for primary-user apps. This can be an alias of the user-specific app-data location.',
  ),
  (
    path: '/data/media',
    description: 'The underlying shared-storage files, including photos, downloads and documents.',
  ),
  (
    path: '/data',
    description: 'Writable app, user and Android service data. Choose a specific subfolder rather than unlocking everything.',
  ),
  (
    path: '/system_ext',
    description: 'System extensions closely tied to the Android framework. Normally a read-only partition.',
  ),
  (
    path: '/system',
    description: 'Core Android framework, system apps, libraries and tools. Normally read-only.',
  ),
  (
    path: '/vendor',
    description: 'Hardware-specific services, libraries and configuration. Normally read-only.',
  ),
  (
    path: '/product',
    description:
        'Product-specific apps, settings and resources. Normally read-only.',
  ),
  (
    path: '/odm',
    description: 'Device-specific hardware customizations. Normally read-only.',
  ),
  (
    path: '/apex',
    description: 'Active modular Android system components. Managed by Android, not an ordinary app folder.',
  ),
  (
    path: '/bootstrap-apex',
    description: 'Android modular components used during early boot. Leave these under Android’s control.',
  ),
  (
    path: '/metadata',
    description: 'Boot and storage metadata; this may include encryption metadata. Not ordinary user files.',
  ),
  (
    path: '/dev',
    description: 'Device interfaces, including raw disks. These entries are not ordinary files.',
  ),
  (
    path: '/proc',
    description: 'Live kernel and process information. Some entries control the running system.',
  ),
  (
    path: '/sys',
    description: 'Live kernel and hardware interfaces. Writes can immediately change device behavior.',
  ),
  (
    path: '/config',
    description: 'Kernel-managed configuration interfaces. These are not ordinary stored documents.',
  ),
  (
    path: '/data_mirror',
    description: 'Internal views of Android data storage. Use App data or Shared storage instead.',
  ),
  (
    path: '/linkerconfig',
    description: 'Generated runtime library-loading configuration. Android manages these files.',
  ),
  (
    path: '/debug_ramdisk',
    description: 'Boot-time debugging and ramdisk-related files, not ordinary user documents.',
  ),
  (
    path: '/mnt',
    description: 'Internal mount points and storage views. Use Shared storage instead of editing through mount aliases.',
  ),
  (
    path: '/storage',
    description: 'User-facing internal and removable storage: photos, downloads and documents.',
  ),
  (
    path: '/sdcard',
    description: 'An alias for shared internal storage, not necessarily a removable SD card.',
  ),
  (
    path: '/cache',
    description: 'Temporary system or recovery files on devices that provide this location.',
  ),
];

String? rootFolderDescription(String path) {
  if (path == '/') {
    return 'The top of Android’s filesystem. Open a folder to see what it contains and whether writes can be unlocked.';
  }
  for (final folder in rootFolderGuide) {
    if (path == folder.path || path.startsWith('${folder.path}/')) {
      return folder.description;
    }
  }
  return null;
}
