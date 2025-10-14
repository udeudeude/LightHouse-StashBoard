import React, { useState, useEffect, useCallback } from 'react';
import Board from './components/Board';
import Calibration from './components/Calibration';

const DPI_STORAGE_KEY = 'lighthouse-dpi';

function App() {
  const [dpi, setDpi] = useState<number | null>(null);
  const [isCalibrating, setIsCalibrating] = useState(false);

  useEffect(() => {
    const savedDpi = localStorage.getItem(DPI_STORAGE_KEY);
    if (savedDpi) {
      setDpi(parseFloat(savedDpi));
    } else {
      // If no DPI is saved, force the calibration screen on first launch.
      setIsCalibrating(true);
    }
  }, []);

  const handleCalibrationComplete = useCallback((calculatedDpi: number) => {
    setDpi(calculatedDpi);
    localStorage.setItem(DPI_STORAGE_KEY, calculatedDpi.toString());
    setIsCalibrating(false);
  }, []);

  const startCalibration = useCallback(() => {
    setIsCalibrating(true);
  }, []);

  // Render nothing until we know whether we have a DPI or need to calibrate,
  // preventing a flash of uncalibrated or empty content.
  if (dpi === null && !isCalibrating) {
    return null;
  }

  return (
    <main className="w-screen h-screen bg-black overflow-hidden select-none">
      {isCalibrating && <Calibration onComplete={handleCalibrationComplete} />}
      {dpi !== null && <Board dpi={dpi} onRecalibrate={startCalibration} />}
    </main>
  );
}

export default App;