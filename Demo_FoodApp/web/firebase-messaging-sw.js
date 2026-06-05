importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBLz1paNFUV35aqD4XbNjf6VmyGKsnN5Hs',
  appId: '1:561027608241:android:38e49cd43adc4e0370fc90',
  messagingSenderId: '561027608241',
  projectId: 'nrk-cfs',
  storageBucket: 'nrk-cfs.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification?.title || 'Food App Notification';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/favicon.png',
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
