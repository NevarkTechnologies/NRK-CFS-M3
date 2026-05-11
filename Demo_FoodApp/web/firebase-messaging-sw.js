importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCMhVaENi5uDnGazWyKn9BWHAddjMnfybI',
  authDomain: 'foodapp-777d6.firebaseapp.com',
  projectId: 'foodapp-777d6',
  storageBucket: 'foodapp-777d6.firebasestorage.app',
  messagingSenderId: '748968496912',
  appId: '1:748968496912:web:51ec7ce5c92cfe6cff1f95',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification?.title || 'Food App Notification';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/favicon.png',
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
