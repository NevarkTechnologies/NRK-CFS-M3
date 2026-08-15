importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBcdjchjHz394BuDCgYTdPGTiFhctu5Cbk',
  appId: '1:561027608241:web:2a72e25cd9c085a470fc90',
  messagingSenderId: '561027608241',
  projectId: 'nrk-cfs',
  authDomain: 'nrk-cfs.firebaseapp.com',
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
