'use strict';

import React, { useState } from 'react';
import { StyleSheet, Button, Text, View } from 'react-native';

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <View style={styles.screen}>
      <Text style={styles.titleText}>Hello, react-native!</Text>
      <Text>You clicked {count} times</Text>
      <Button onPress={() => setCount(count + 1)} title="Press Me" />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: 'red',
    flex: 1,
    justifyContent: "center",
    alignItems: "center"
  },
  titleText: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 10,
  },
});
