"use client";

import { motion } from "framer-motion";
import { Github, Heart, Linkedin, Coffee } from "lucide-react";
import { Button } from "~/components/ui/button";
import { useEffect, useState } from "react";

export default function Footer() {
  const [year, setYear] = useState<number>(2024);

  useEffect(() => {
    setYear(new Date().getFullYear());
  }, []);

  return (
    <footer className="border-t py-8">
      <div className="container mx-auto flex flex-col items-center gap-4 px-4 md:grid md:grid-cols-3 md:items-center">
        <div className="flex items-center gap-2 md:justify-start">
          <p className="text-muted-foreground text-sm">
            &copy; {year}{" "}
            <a
              href="https://www.linkedin.com/in/ugurkocde/"
              target="_blank"
              rel="noopener noreferrer"
              className="transition-colors hover:text-blue-600 hover:underline dark:hover:text-blue-400 underline-offset-4"
            >
              Ugur Koc
            </a>
          </p>
        </div>

        <div className="text-muted-foreground flex items-center gap-2 text-sm md:justify-center">
          <span>Made with</span>
          <Coffee className="h-4 w-4 fill-amber-600 text-amber-600" />
          <span>and</span>
          <Heart className="h-4 w-4 fill-red-500 text-red-500" />
          <span>by </span>
          <a
            href="https://www.linkedin.com/in/ugurkocde/"
            target="_blank"
            rel="noopener noreferrer"
            className="transition-colors hover:text-blue-600 hover:underline dark:hover:text-blue-400 underline-offset-4"
          >
            Ugur
          </a>
        </div>

        <div className="flex items-center gap-2 md:justify-end">
          <motion.div whileHover={{ scale: 1.05 }} whileTap={{ scale: 0.95 }}>
            <Button asChild variant="outline" size="sm" className="gap-2">
              <a
                href="https://www.linkedin.com/in/ugurkocde/"
                target="_blank"
                rel="noopener noreferrer"
              >
                <Linkedin className="h-4 w-4" />
                <span>Connect</span>
              </a>
            </Button>
          </motion.div>

          <motion.div whileHover={{ scale: 1.05 }} whileTap={{ scale: 0.95 }}>
            <Button asChild variant="outline" size="sm" className="gap-2">
              <a
                href="https://github.com/ugurkocde/IntuneAutomation"
                target="_blank"
                rel="noopener noreferrer"
              >
                <Github className="h-4 w-4" />
                <span>GitHub</span>
              </a>
            </Button>
          </motion.div>
        </div>
      </div>
    </footer>
  );
}
